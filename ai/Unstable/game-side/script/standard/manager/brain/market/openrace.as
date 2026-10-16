namespace Market {

// THE OPENING RACE (apex_open_race, his 2026-10-16: their labs open with raiders, ours with cons;
// time a con's build and walk against a fighter's and start with military where it arrives in time).
// One clock and one horizon H = PayH(), each priced per metal (energy at ConvRate):
//   tB      = build seconds at the line / feed share, the share min(1, metal, energy) with its own draw
//   hold(A) = A / (A + arrive), A = our side's army + our queued army, arrive = smallhard's
//   tR      = their raiders at our eco: 0 once their army is seen, else our lab's start (their
//             lab mirrors ours) + their cheapest fighter's build + smallhard's path Tc
//   con     = spot yield x surv(t_j) over its share of our side's open spots (job j ready at
//             tB + j x (walk + mex build)), then the best generation rung x the hands share;
//             surv(t) = seconds to H before tR + hold(A) x seconds after
//   fighter = kills x (extractor metal + yield x (rebuild + SmallHardDenyS(rebuild)))
//             + (hold(A + c) - hold(A)) x team income x (H - max(tR, tB));
//             kills = min((H - tA) x hold(A + c) / (hp/dps + gap/speed), their likely spots x c/(A + c)),
//             tA = tB + smallhard walk / speed, c = its strength in basic-fighter metal (smallhard's)
// The con floor's order goes to the better; a lab under an energy stall prices each unit by its feed
// share instead of ordering nothing. Inert without apex_small_hard (walk, arrive, Tc, their spots).

bool gOrcOn = false;
bool gOrcRead = false;
int gOrcLabAt = -1;
int gOrcGroundAt = -999999;
float gOrcOpenN = 0.f;
float gOrcSpotD = 0.f;
int gOrcAt = -1, gOrcFid = -1, gOrcSlot = -1, gOrcPick = -1;
int gOrcAsk = 0, gOrcFighterN = 0, gOrcStallN = 0, gOrcStallFacN = 0, gOrcNoWalk = 0;
float gOrcCostUs = 0.f;
int gOrcStatAt = 0;
int gOrcHAt = -1;
float gOrcH = 0.f;
int gOrcMex = 0;

int OpenRaceMex()
{
	if (gOrcMex <= 0)
		gOrcMex = ClaimExtractDef(false);
	return gOrcMex;
}

bool OpenRaceOn()
{
	if (!gOrcRead) {
		gOrcRead = true;
		gOrcOn = ai.GetTunable("apex_open_race", TUNE_OPEN_RACE) > 0.f;
	}
	return gOrcOn && SmallHardOn();
}

// The lathe's speed on `d` while the feeds are short: each feed's share of what is pulled from it,
// this unit's own draw added; the bank counts over the time a generator takes to stand.
float OpenRaceFeed(int d, float bs)
{
	if (bs <= 0.1f)
		return 1.f;
	if (gOrcHAt != ai.frame) {
		gOrcHAt = ai.frame;
		gOrcH = EGenBuildSeconds();
	}
	const float sec = gOrcH;
	const float h = (sec > 1.f) ? sec : 1.f;
	float s = 1.f;
	const float mP = Eco::MPull() + Catalog::gCostM[d] / bs;
	if (mP > 0.01f) {
		const float ms = (Eco::MInc() + Eco::MCur() / h) / mP;
		if (ms < s)
			s = ms;
	}
	const float eP = Eco::EPull() + Catalog::gCostE[d] / bs;
	if (eP > 0.01f) {
		const float es = (Eco::EInc() + Eco::ECur() / h) / eP;
		if (es < s)
			s = es;
	}
	return (s > 0.01f) ? s : 0.01f;
}

float OpenRaceCostEq(int d)
{
	return Catalog::gCostM[d] + Catalog::gCostE[d] * ConvRate();
}

// Our side's open spots and their mean distance from home; 5 s cache.
void OpenRaceGround()
{
	if (ai.frame - gOrcGroundAt < 5 * SECOND)
		return;
	gOrcGroundAt = ai.frame;
	gOrcOpenN = 0.f;
	gOrcSpotD = 0.f;
	if (!Builder::gHomeSet)
		return;
	CacheSpots();
	const bool ms = (gMsHeld.length() == gAllSpots.length()) && (gAllSpots.length() > 0);
	const array<int>@ lidx = LedgerIdx();
	const bool side = OnMap(gSmhBox);
	const AIFloat3 home = Builder::gHomePos;
	float sum = 0.f;
	int n = 0;
	for (uint s = 0; s < gAllSpots.length(); ++s) {
		const AIFloat3 p = gAllSpots[s];
		if (!OnMap(p))
			continue;
		if (ms ? (gMsHeld[s] != 0) : ((int(s) < int(lidx.length())) && (lidx[s] >= 0)))
			continue;
		if (side && (p.distance2D(gSmhBox) < p.distance2D(home)))
			continue;
		sum += p.distance2D(home);
		++n;
	}
	gOrcOpenN = side ? float(n) : float(n) * 0.5f;
	gOrcSpotD = (n > 0) ? sum / float(n) : 0.f;
}

float OrcSurv(float t0, float H, float tR, float hold)
{
	if (t0 >= H)
		return 0.f;
	float safe = ((tR < H) ? tR : H) - t0;
	if (safe < 0.f)
		safe = 0.f;
	float risky = H - ((t0 > tR) ? t0 : tR);
	if (risky < 0.f)
		risky = 0.f;
	return safe + hold * risky;
}

float OpenRaceConV(int cd, float lineBp, float H, float tR, float hold0, string &out terms)
{
	terms = "";
	const float v = Catalog::gSpeed[cd];
	const float bp = Catalog::gBuildPower[cd];
	if ((lineBp <= 0.f) || (v <= 1.f) || (bp <= 0.f))
		return 0.f;
	const float bs = Catalog::gBuildTime[cd] / lineBp;
	const float tB = bs / OpenRaceFeed(cd, bs);
	const int mex = OpenRaceMex();
	const float walk = gOrcSpotD / v;
	const float btMex = (mex > 0) ? Catalog::gBuildTime[mex] / bp : 0.f;
	const float hands = float(ConsOwnedAny() + ConsInFlightAny() + 1);
	const float share = gOrcOpenN / (hands + 1.f);
	const float dI = SpotM();
	float t = tB;
	float V = 0.f;
	string sT = "";
	if (SpotRaceOn()) {
		float tFree = tB;
		V = SpotRaceConM(cd, tB, H, tR, hold0, tFree, sT);
		t = tFree;
	} else {
		float left = (mex > 0) ? share : 0.f;
		for (int j = 0; (j < 64) && (left > 0.f) && (t < H); ++j) {
			t += walk + btMex;
			V += ((left < 1.f) ? left : 1.f) * dI * OrcSurv(t, H, tR, hold0);
			left -= 1.f;
		}
	}
	const float vSpot = V;
	int gd = 0;
	float gG = 0.f;
	PoolRefresh();
	if (gPoolNow !is null) {
		for (uint i = 0; i < gPoolNow.def.length(); ++i) {
			if (!gPoolNow.mob[i]) {
				gd = gPoolNow.def[i];
				gG = gPoolNow.gain[i];
				break;
			}
		}
	}
	const float hs = EtaHandsShare();
	if ((gd > 0) && (gG > 0.f) && (hs > 0.f)) {
		float cyc = Catalog::gBuildTime[gd] / bp;
		if (cyc < 1.f)
			cyc = 1.f;
		for (int k = 0; (k < 64) && (t + cyc < H); ++k) {
			t += cyc;
			V += gG * hs * OrcSurv(t, H, tR, hold0);
		}
	}
	terms = " tB=" + int(tB) + " walk=" + int(walk) + " share=" + NnF(share, 1) + " dI=" + NnF(dI, 2)
		+ " spot=" + int(vSpot) + sT + " gen=" + ((gd > 0) ? Catalog::Def(gd).GetName() : "-") + "x" + NnF(hs, 2);
	return V;
}

float OpenRaceFighterV(int fd, float lineBp, float H, float tR, float A, float arrive, float hold0,
	float iTeam, int conDef, string &out terms)
{
	terms = "";
	const float spd = Catalog::gSpeed[fd];
	const float dps = Catalog::gDps[fd];
	if ((lineBp <= 0.f) || (spd <= 1.f) || (dps <= 0.f))
		return 0.f;
	const float walkE = (gSmhWalk > 0.f) ? gSmhWalk : ((gSmhTc > 0.f) ? gSmhTc * gRushSpd : -1.f);
	if (walkE < 0.f)
		return 0.f;
	// basic-fighter metal by the square law: UnitStrength is dps x hp, so one unit of k times a basic
	// one's strength fights like sqrt(k) of them (linear, a Centurion read 3143 m for 270)
	// Speed is not strength here: it is already in tA and tau below.
	const int bd = gSmhWalkDef;
	const float sBasic = (bd > 0) ? Catalog::gDps[bd] * Catalog::gHealth[bd] : 0.f;
	const float c = (sBasic > 0.f) ? sqrt(dps * Catalog::gHealth[fd] / sBasic) * Catalog::gCostM[bd] : Catalog::gCostM[fd];
	const float bs = Catalog::gBuildTime[fd] / lineBp;
	const float tB = bs / OpenRaceFeed(fd, bs);
	const float tA = tB + walkE / spd;
	const float holdF = (A + c + arrive > 1.f) ? (A + c) / (A + c + arrive) : 1.f;
	float kills = 0.f;
	float perKill = 0.f;
	const int mex = OpenRaceMex();
	if ((mex > 0) && (tA < H)) {
		const float tau = Catalog::gHealth[mex] / dps + gOrcSpotD / spd;
		// It kills only while alive: their army there and their commander, fire spread by count.
		float win = H - tA;
		const float eDps = (gEbArmyAt + gEbRs * tA) * gEbQD + gEbComDps;
		if (eDps > 0.f) {
			const float life = Catalog::gHealth[fd] * (A + c) / (Catalog::gCostM[fd] * eDps);
			if (life < win)
				win = life;
		}
		kills = (tau > 0.1f) ? win * holdF / tau : 0.f;
		const float nF = float(gSmhFoeSeenN) + float(gSmhFoeLikelyN) * gSmhOcc;
		const float cap = nF * c / (A + c);
		if (kills > cap)
			kills = cap;
		const float vc = Catalog::gSpeed[conDef];
		const float bpc = Catalog::gBuildPower[conDef];
		const float rebuild = ((vc > 1.f) ? gOrcSpotD / vc : 0.f)
				+ ((bpc > 0.f) ? Catalog::gBuildTime[mex] / bpc : 0.f);
		perKill = Catalog::gCostM[mex] + SpotM() * (rebuild + SmallHardDenyS(rebuild));
	}
	const float deny = kills * perKill;
	const float tP = (tR > tB) ? tR : tB;
	const float prot = (tP < H) ? (holdF - hold0) * iTeam * (H - tP) : 0.f;
	terms = " tB=" + int(tB) + " tA=" + int(tA) + " str=" + int(c) + " holdF=" + NnF(holdF, 2) + " kills=" + NnF(kills, 1)
		+ " deny=" + int(deny) + " prot=" + int(prot);
	return deny + prot;
}

// The race's clock: horizon, their raiders' arrival, our army and its hold against what arrives.
void OpenRaceClock(int fid, float &out H, float &out tR, float &out A, float &out arrive, float &out hold0)
{
	const int labAt = (gOrcLabAt >= 0) ? gOrcLabAt : ai.frame;
	PrTuneFill();
	H = PayH();
	arrive = gSmhArrive;
	A = Military::TeamArmyCost() + ArmyInFlightM();
	if (A < 0.f)
		A = 0.f;
	hold0 = (A + arrive > 1.f) ? A / (A + arrive) : 1.f;
	tR = H;
	if (gSmhSeen > 1.f) {
		tR = 0.f;
	} else if ((gSmhTc >= 0.f) && (gSmhWalkDef > 0) && (fid > 0) && (Catalog::gBuildPower[fid] > 0.f)) {
		tR = float(labAt - ai.frame) / float(SECOND)
				+ Catalog::gBuildTime[gSmhWalkDef] / Catalog::gBuildPower[fid] + gSmhTc;
		if (tR < 0.f)
			tR = 0.f;
	}
}

// The con floor asks: the lab's best fighter by the race, or -1 when the con pays more.
int OpenRacePick(CCircuitUnit@ fac, int fid, const array<int>@ prods, int conDef, int slot)
{
	if ((ai.frame == gOrcAt) && (int(fac.id) == gOrcFid) && (slot == gOrcSlot))
		return gOrcPick;
	const double _t0 = ai.ClockUs();
	gOrcAt = ai.frame;
	gOrcFid = int(fac.id);
	gOrcSlot = slot;
	gOrcPick = -1;
	++gOrcAsk;
	if (gOrcLabAt < 0)
		gOrcLabAt = ai.frame;
	OpenRaceGround();
	const float lineBp = Brain::LineBuildPower(fac);
	float H, tR, A, arrive, hold0;
	OpenRaceClock(fid, H, tR, A, arrive, hold0);
	array<Id>@ mates = ai.GetTeamIds();
	const int ours = ((mates is null) || (mates.length() < 1)) ? 1 : int(mates.length());
	const float iTeam = Eco::MInc() * float(ours);
	string cT;
	const float vC = OpenRaceConV(conDef, lineBp, H, tR, hold0, cT);
	const float rC = vC / OpenRaceCostEq(conDef);
	int best = -1;
	float rBest = 0.f, vBest = 0.f;
	string fT = "";
	for (uint i = 0; (prods !is null) && (i < prods.length()); ++i) {
		const int pd = prods[i];
		if (!Catalog::gAvailable[pd] || !Catalog::gMobile[pd] || Catalog::gBuilder[pd] || Catalog::gFlyer[pd]
			|| Catalog::gKamikaze[pd] || !Catalog::gHitsLand[pd] || !LineCombat(pd))
			continue;
		string t;
		const float vF = OpenRaceFighterV(pd, lineBp, H, tR, A, arrive, hold0, iTeam, conDef, t);
		const float rF = vF / OpenRaceCostEq(pd);
		if (rF > rBest) {
			rBest = rF;
			vBest = vF;
			best = pd;
			fT = t;
		}
	}
	if ((gSmhWalk <= 0.f) && (gSmhTc <= 0.f))
		++gOrcNoWalk;
	if ((best > 0) && (rBest > rC)) {
		gOrcPick = best;
		++gOrcFighterN;
	}
	SpotRaceNoteAsk(rC, rBest, gOrcPick > 0);
	gOrcCostUs += float(ai.ClockUs() - _t0);
	if (ai.frame < 10 * MINUTE)
		AiLog(Factory::T() + "apex: openrace-stat t=" + ai.teamId + " fac=" + fac.circuitDef.GetName()
			+ " #" + fac.id + " slot=" + slot + " H=" + int(H) + " tR=" + int(tR) + " A=" + int(A)
			+ " arrive=" + int(arrive) + " hold=" + NnF(hold0, 2) + " iTeam=" + NnF(iTeam, 1)
			+ " | con " + Catalog::Def(conDef).GetName() + " r=" + NnF(rC, 2) + " v=" + int(vC) + cT
			+ " | fighter " + ((best > 0) ? Catalog::Def(best).GetName() : "-") + " r=" + NnF(rBest, 2)
			+ " v=" + int(vBest) + fT
			+ " -> " + ((gOrcPick > 0) ? Catalog::Def(gOrcPick).GetName() : Catalog::Def(conDef).GetName()));
	return gOrcPick;
}

// Each candidate's value at its feed share, the army's uniform energy throttle taken back out.
float OpenRaceFeedPrice(CCircuitUnit@ fac, array<int>@ candDef, array<float>@ candV, array<float>@ candGain,
	float sumV, float eFeedA, int rezDef, bool stalled)
{
	if (stalled)
		++gOrcStallFacN;
	const float lineBp = Brain::LineBuildPower(fac);
	if (lineBp <= 0.f)
		return sumV;
	for (uint i = 0; i < candDef.length(); ++i) {
		const int d = candDef[i];
		float s = OpenRaceFeed(d, Catalog::gBuildTime[d] / lineBp);
		if (!Catalog::gBuilder[d] || (d == rezDef)) {
			s = (eFeedA > 0.01f) ? s / eFeedA : s;
			if (s > 1.f)
				s = 1.f;
		}
		sumV += candV[i] * (s - 1.f);
		candV[i] *= s;
		candGain[i] *= s;
	}
	return sumV;
}

void OpenRaceNoteStall()
{
	++gOrcStallN;
}

void OpenRaceNoteOrder(const CCircuitDef@ o)
{
	if ((o is null) || !OpenRaceOn())
		return;
	const int d = int(o.id);
	Brain::BudgetHoldNoteOrder(Catalog::gCostM[d], Catalog::gBuilder[d] || Catalog::gRezzer[d]);
	SpotRaceNoteOrder(d);
}

void OpenRaceUpdate()
{
	if (!OpenRaceOn())
		return;
	SpotRaceUpdate();
	if (ai.frame < gOrcStatAt)
		return;
	gOrcStatAt = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: openrace-sum t=" + ai.teamId + " asked=" + gOrcAsk + " fighter=" + gOrcFighterN
		+ " estallPriced=" + gOrcStallN + "/" + gOrcStallFacN + " noWalk=" + gOrcNoWalk
		+ " open=" + NnF(gOrcOpenN, 1) + " spotD=" + int(gOrcSpotD)
		+ " us=" + int(gOrcCostUs) + " usPer=" + int((gOrcAsk > 0) ? gOrcCostUs / float(gOrcAsk) : 0.f));
	gOrcAsk = 0;
	gOrcFighterN = 0;
	gOrcStallN = 0;
	gOrcStallFacN = 0;
	gOrcNoWalk = 0;
	gOrcCostUs = 0.f;
}

}  // namespace Market
