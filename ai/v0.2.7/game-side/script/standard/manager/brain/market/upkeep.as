namespace Market {

// TUNE_UNIT_UPKEEP: every mobile body a factory adds is charged a slot price in metal,
//   price = lag * (team mobile metal / team mobile bodies) / (1 - team bodies / team cap)
// and its draw weight keeps cost / (cost + price). Zero while the game runs at its set speed.
const int BOARD_UPKEEP_N = 3300, BOARD_UPKEEP_M = 3400, BOARD_UPKEEP_AT = 3500;
const int UK_GND = 0, UK_AIR = 1, UK_CON = 2, UK_REZ = 3, UK_CLS = 4;

array<Id>@ gUkMates = null;
int gUkMaxUnits = -1;
int gUkNMine = 0, gUkNTeam = 0, gUkSeats = 0;
float gUkMMine = 0.f, gUkMTeam = 0.f;
float gUkLag = 0.f, gUkRho = 0.f, gUkBody = 0.f, gUkPrice = 0.f;

array<float> gUkPre;
array<float> gUkPost;
array<float> gUkLost;
array<int> gUkTouched;
array<float> gUkKeepSum(UK_CLS, 0.f);
array<int> gUkKeepN(UK_CLS, 0);
int gUkAsk = 0, gUkCut = 0, gUkNone = 0, gUkShift = 0, gUkUp = 0, gUkFloorSkip = 0;
int gNextUkLog = 0;

bool UpkeepOn()
{
	return ai.GetTunable("apex_unit_upkeep", TUNE_UNIT_UPKEEP) > 0.f;
}

int UkMaxUnits()
{
	if (gUkMaxUnits < 0) {
		gUkMaxUnits = int(parseInt(string(aiSetupMgr.GetModOptions()["maxunits"])));
		if (gUkMaxUnits <= 0)
			gUkMaxUnits = 2000;
	}
	return gUkMaxUnits;
}

int UkClass(int d)
{
	if (Catalog::gRezzer[d])
		return UK_REZ;
	if (Catalog::gBuilder[d])
		return UK_CON;
	return Catalog::gFlyer[d] ? UK_AIR : UK_GND;
}

float UpkeepKeep(int d)
{
	if ((gUkPrice <= 0.f) || !Catalog::ValidId(d) || !Catalog::gMobile[d])
		return 1.f;
	const float c = Catalog::gCostM[d];
	return (c > 0.f) ? c / (c + gUkPrice) : 1.f;
}

// AiUpdate, every other call: our census to the board, the team's back.
void UpkeepTick()
{
	int n = 0;
	float m = 0.f;
	const array<int>@ own = OwnedDefs();
	for (uint i = 0; i < own.length(); ++i) {
		const int d = own[i];
		if (!Catalog::gMobile[d])
			continue;
		n += gOwnCount[d];
		m += float(gOwnCount[d]) * Catalog::gCostM[d];
	}
	gUkNMine = n;
	gUkMMine = m;
	ai.SetTeamBoard(BOARD_UPKEEP_N + ai.teamId, float(n));
	ai.SetTeamBoard(BOARD_UPKEEP_M + ai.teamId, m);
	ai.SetTeamBoard(BOARD_UPKEEP_AT + ai.teamId, float(ai.frame));
	if (gUkMates is null)
		@gUkMates = ai.GetTeamIds();
	int nT = n, seats = 1;
	float mT = m;
	for (uint i = 0; (gUkMates !is null) && (i < gUkMates.length()); ++i) {
		const int t = int(gUkMates[i]);
		if (t == ai.teamId)
			continue;
		const float at = ai.GetTeamBoard(BOARD_UPKEEP_AT + t, -1.f);
		if ((at < float(ai.frame - 10 * SECOND)) || (at > float(ai.frame)))
			continue;   // not one of ours, or gone quiet
		nT += int(ai.GetTeamBoard(BOARD_UPKEEP_N + t, 0.f));
		mT += ai.GetTeamBoard(BOARD_UPKEEP_M + t, 0.f);
		++seats;
	}
	gUkNTeam = nT;
	gUkMTeam = mT;
	gUkSeats = seats;
	gUkLag = Perf::LagSeverity() / 3.f;
	if (gUkLag > 1.f)
		gUkLag = 1.f;
	gUkRho = float(nT) / float(seats * UkMaxUnits());
	if (gUkRho > 0.99f)
		gUkRho = 0.99f;
	gUkBody = (nT > 0) ? mT / float(nT) : 0.f;
	gUkPrice = gUkLag * gUkBody / (1.f - gUkRho);
	UpkeepLog();
}

// The draw's candidates: fills the with/without weights, applies them when on, and
// returns the weight moved to the no-order ticket (also in shadow, for the stat).
float UpkeepCharge(const array<int>&in defs, array<float>& vals)
{
	if (gUkPrice <= 0.f)
		return 0.f;
	const bool on = UpkeepOn();
	const uint n = defs.length();
	gUkPre.resize(n);
	gUkPost.resize(n);
	float moved = 0.f;
	bool cut = false;
	for (uint i = 0; i < n; ++i) {
		const int d = defs[i];
		const float k = UpkeepKeep(d);
		gUkPre[i] = vals[i];
		gUkPost[i] = vals[i] * k;
		if (k < 1.f) {
			cut = true;
			moved += vals[i] - gUkPost[i];
			const int cls = UkClass(d);
			gUkKeepSum[cls] += k;
			gUkKeepN[cls] += 1;
			if (on)
				vals[i] = gUkPost[i];
		}
	}
	++gUkAsk;
	if (cut)
		++gUkCut;
	return moved;
}

int UkPick(const array<float>&in v, float roll)
{
	for (uint i = 0; i < v.length(); ++i) {
		roll -= v[i];
		if (roll <= 0.f)
			return int(i);
	}
	return -1;
}

// After the draw: what the same roll picks with and without the charge.
void UpkeepNote(const array<int>&in defs, float sumV, float frac)
{
	if ((gUkPrice <= 0.f) || (gUkPre.length() != defs.length()) || (sumV <= 0.f))
		return;
	const int a = UkPick(gUkPre, frac * sumV);
	const int b = UkPick(gUkPost, frac * sumV);
	if (a != b) {
		++gUkShift;
		if (b < 0)
			++gUkNone;
		else if ((a >= 0) && (Catalog::gCostM[defs[b]] > Catalog::gCostM[defs[a]]))
			++gUkUp;
	}
	if (int(gUkLost.length()) <= Catalog::gDefCount)
		gUkLost.resize(Catalog::gDefCount + 1);
	for (uint i = 0; i < defs.length(); ++i) {
		const float l = (gUkPre[i] - gUkPost[i]) / sumV;
		if (l <= 0.f)
			continue;
		if (gUkLost[defs[i]] <= 0.f)
			gUkTouched.insertLast(defs[i]);
		gUkLost[defs[i]] += l;
	}
}

// A floor orders ahead of the draw; under the charge it fires at the unit's keep and
// otherwise leaves the unit to be priced in the draw.
bool UpkeepFloorPasses(int d, CCircuitUnit@ fac, int slot)
{
	const float k = UpkeepKeep(d);
	if (k >= 1.f)
		return true;
	uint h = uint(ai.frame) * 2246822519 + uint(fac.id) * 40503 + uint(slot) * 2654435761 + uint(d) * 97;
	h ^= (h >> 13);
	if (float(h % 10000) / 10000.f < k)
		return true;
	++gUkFloorSkip;
	return !UpkeepOn();
}

void UpkeepLog()
{
	if (ai.frame < gNextUkLog)
		return;
	gNextUkLog = ai.frame + 60 * SECOND;
	string keep = "";
	for (int c = 0; c < UK_CLS; ++c) {
		keep += ((c > 0) ? "/" : "") + ((gUkKeepN[c] > 0)
			? formatFloat(gUkKeepSum[c] / float(gUkKeepN[c]), "", 0, 2) : "-");
		gUkKeepSum[c] = 0.f;
		gUkKeepN[c] = 0;
	}
	string top = "";
	for (int r = 0; r < 3; ++r) {
		int bi = -1;
		for (uint i = 0; i < gUkTouched.length(); ++i) {
			const int d = gUkTouched[i];
			if ((gUkLost[d] > 0.f) && ((bi < 0) || (gUkLost[d] > gUkLost[gUkTouched[bi]])))
				bi = int(i);
		}
		if (bi < 0)
			break;
		const int bd = gUkTouched[bi];
		top += ((r > 0) ? "," : "") + Catalog::Def(bd).GetName() + ":" + formatFloat(gUkLost[bd], "", 0, 1);
		gUkLost[bd] = -gUkLost[bd];
	}
	for (uint i = 0; i < gUkTouched.length(); ++i)
		gUkLost[gUkTouched[i]] = 0.f;
	gUkTouched.resize(0);
	AiLog(Factory::T() + "apex: upkeep-stat t=" + ai.teamId + " on=" + (UpkeepOn() ? 1 : 0)
		+ " lag=" + formatFloat(gUkLag, "", 0, 2) + " speed=" + formatFloat(Perf::SimSpeed(), "", 0, 2)
		+ " mine=" + gUkNMine + "/" + int(gUkMMine) + " team=" + gUkNTeam + "/" + int(gUkMTeam)
		+ " seats=" + gUkSeats + " rho=" + formatFloat(gUkRho, "", 0, 3)
		+ " body=" + int(gUkBody) + " price=" + int(gUkPrice)
		+ " keep(gnd/air/con/rez)=" + keep
		+ " asks=" + gUkAsk + " cut=" + gUkCut + " shift=" + gUkShift + " none=" + gUkNone
		+ " up=" + gUkUp + " floorSkip=" + gUkFloorSkip + " top=" + top);
	gUkAsk = 0;
	gUkCut = 0;
	gUkShift = 0;
	gUkNone = 0;
	gUkUp = 0;
	gUkFloorSkip = 0;
}

}  // namespace Market
