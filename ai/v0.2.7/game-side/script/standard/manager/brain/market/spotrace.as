namespace Market {

// THE SPOT RACE (apex_open_race; c9 vs BARb hard, Red Comet: they held 17-22 extractors by minute
// 6-8, we 8-11). An open spot pays the side whose hand reaches it first. Refreshed every 5 s.
//   their arrival  tF(s) = min(a seen con: walk + build, their queue: rank from their box / rate
//                  + walk from their box); rate = hands / (build + spacing / speed), hands = their
//                  commanders + max(cons seen, ours mirrored) + seen air cons at their own cycle
//   P(t)           = tF / (t + tF)                   two exponential clocks racing
//   val(t)         = yield x P(t) x (surv(t) + (1 - hold) x (H - max(t, tF)))   ours, and theirs denied
// Our side's queue: every open spot ranked from our nearest base (our home, an ally's plant); the
// team's hands h (each seat's cons + its commander's share of time on extractors, published) reach
// rank r at r / R + walk, R = h / cycle. A new hand (speed v, power b, ready at tB, rho = 1 / its
// cycle) reaches it at min(that, (r + rho tB) / (R + rho) + walk from our home / v); the con is worth
// the sum of val(with) - val(without). Air cons price the same way at their own speed.
// The army's targets: their extractors, their cons (the claims lost while one is replaced) and open
// spots whose race a held position flips, each net = prize (1 - L) - L x M at the local defence
// (square law L); the launch bar is the chosen target's local need, the base ball one target.

const string TV_SPR_HANDS = "sprHands";
int gSprAt = -999999;
bool gSprHave = false;
float gSprSpace = -1.f;
float gSprComMex = 1.f;
float gSprHandsUs = 0.f, gSprRUs = 0.f;
array<int> gSprS;
array<float> gSprD, gSprTh, gSprY, gSprT0;
array<float> gSprThOf;
array<int> gSprIdxOf;
float gSprYMean = 0.f;
int gSprOpenAll = 0;
float gSprRate = 0.f, gSprHandsF = 0.f, gSprVF = 0.f, gSprCycF = 0.f;
int gSprFcGN = 0, gSprFcAN = 0;
array<AIFloat3> gSprFcPW, gSprFcP;
array<int> gSprFcDW, gSprFcD;
array<int> gSprHist = {0, 0, 0, 0, 0};
int gSprLogAt = 1800;
int gSprAsk = 0, gSprAskF = 0;
float gSprRCSum = 0.f, gSprRFSum = 0.f;
int gSprOrdCon = 0, gSprOrdAir = 0, gSprOrdFig = 0;
float gSprCostUs = 0.f;
int gSprCalls = 0;
int gSprKind = 0;
float gSprKNet = 0.f, gSprKE = 0.f, gSprKPrize = 0.f, gSprKF = 0.f;
float gSprBallW = 0.f, gSprPerM = 0.f;
int gSprBarN = 0, gSprBallN = 0;
float gSprBarSum = 0.f;
int gSprGoN = 0, gSprRaidN = 0;
float gSprGoSize = 0.f, gSprGoNeed = 0.f, gSprRaidSize = 0.f, gSprRaidNeed = 0.f;
float gSprKillM = 0.f;
const array<string> SPR_KINDS = {"-", "mex", "con", "spot"};

bool SpotRaceOn()
{
	return OpenRaceOn() && (SmallHardK() > 0.f);
}

void SprFoeBegin()
{
	gSprFcPW.resize(0);
	gSprFcDW.resize(0);
}

// From the map-share sweep: their constructors we see or hold on radar now.
void SprFoeNote(int i, int d)
{
	if (!Catalog::gBuilder[d] || Catalog::gRezzer[d] || (Catalog::gSpeed[d] <= 1.f) || (Catalog::gBuildPower[d] <= 0.f)
		|| Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask))
		return;
	const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
	if ((los < 0) || ((los & 3) == 0) || ((los & (4 | 8 | 32 | 64)) != 0))
		return;
	const AIFloat3 p = aiEnemyMgr.GetEnemyUnitPosAt(i);
	if (!OnMap(p))
		return;
	gSprFcPW.insertLast(p);
	gSprFcDW.insertLast(d);
}

void SprFoeFinish()
{
	gSprFcP = gSprFcPW;
	gSprFcD = gSprFcDW;
}

// Mean nearest-neighbour distance between spots, from a sample of them.
void SprSpacing()
{
	const uint n = gAllSpots.length();
	gSprSpace = 0.f;
	if (n < 2)
		return;
	const uint m = (n < 64) ? n : 64;
	const uint step = n / m;
	float sum = 0.f;
	int k = 0;
	for (uint a = 0; a < n; a += ((step > 0) ? step : 1)) {
		float best = -1.f;
		for (uint b = 0; b < n; ++b) {
			if (b == a)
				continue;
			const float dd = gAllSpots[a].distance2D(gAllSpots[b]);
			if ((dd > 1.f) && ((best < 0.f) || (dd < best)))
				best = dd;
		}
		if (best > 0.f) {
			sum += best;
			++k;
		}
	}
	gSprSpace = (k > 0) ? sum / float(k) : 0.f;
}

float SprVal(float y, float t, float tF, float H, float tR, float hold)
{
	if (t >= H)
		return 0.f;
	const float P = (tF > 0.f) ? tF / (t + tF) : 0.f;
	float den = H - ((t > tF) ? t : tF);
	den = (den > 0.f) ? den * (1.f - hold) : 0.f;
	return y * P * (OrcSurv(t, H, tR, hold) + den);
}

void SprRefresh()
{
	gSprAt = ai.frame;
	gSprHave = false;
	gSprS.resize(0);
	gSprD.resize(0);
	gSprTh.resize(0);
	gSprY.resize(0);
	gSprT0.resize(0);
	gSprOpenAll = 0;
	const uint n = gAllSpots.length();
	if (!Builder::gHomeSet || (n == 0) || (gMsHeld.length() != n) || !OnMap(gSmhBox))
		return;
	const int mex = OpenRaceMex();
	if (mex <= 0)
		return;
	if (gSprSpace < 0.f)
		SprSpacing();
	gSprThOf.resize(n);
	const AIFloat3 home = Builder::gHomePos;
	const AIFloat3 box = gSmhBox;
	const float ext = Catalog::gExtractsM[mex] * IncomeMult();
	const float btMex = Catalog::gBuildTime[mex];
	const float v0 = Military::NrConSpeed();
	const float bp0 = (Military::gNrConBP > 0.f) ? Military::gNrConBP : 1.f;
	// their hands: seen cons by kind, the rest mirrored from ours
	float sG = 0.f, cycA = 0.f;
	gSprFcGN = 0;
	gSprFcAN = 0;
	for (uint i = 0; i < gSprFcD.length(); ++i) {
		const int d = gSprFcD[i];
		if (Catalog::gFlyer[d]) {
			++gSprFcAN;
			cycA += btMex / Catalog::gBuildPower[d] + gSprSpace / Catalog::gSpeed[d];
		} else {
			++gSprFcGN;
			sG += Catalog::gSpeed[d];
		}
	}
	const float vF = (gSprFcGN > 0) ? sG / float(gSprFcGN) : v0;
	const float cycG = btMex / bp0 + gSprSpace / ((vF > 1.f) ? vF : 1.f);
	const float foes = float((gSmhFoes > 0) ? gSmhFoes : 1);
	const float mirror = float(ConsOwnedAny() + ConsInFlightAny()) * foes;
	const float handsG = foes + ((float(gSprFcGN) > mirror) ? float(gSprFcGN) : mirror);
	float rate = (cycG > 0.1f) ? handsG / cycG : 0.f;
	if ((gSprFcAN > 0) && (cycA > 0.1f))
		rate += float(gSprFcAN) * float(gSprFcAN) / cycA;
	gSprRate = rate;
	gSprHandsF = handsG + float(gSprFcAN);
	gSprVF = vF;
	gSprCycF = cycG;
	// our side's bases: our home and one plant per ally base; our side's hands, as each seat publishes
	AllyStaticsSync();
	array<AIFloat3> bases;
	bases.insertLast(home);
	const float dedup = (gSprSpace > 1.f) ? gSprSpace : 1.f;
	for (uint i = 0; i < gAllyPlPos.length(); ++i) {
		bool near = false;
		for (uint k = 0; k < bases.length(); ++k) {
			if (bases[k].distance2D(gAllyPlPos[i]) < dedup) {
				near = true;
				break;
			}
		}
		if (!near)
			bases.insertLast(gAllyPlPos[i]);
	}
	const float hMine = float(ConsOwnedAny() + ConsInFlightAny()) + gSprComMex;
	ai.PublishTeamValue(TV_SPR_HANDS, hMine);
	float hTeam = 0.f;
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0)) {
		hTeam = hMine;
	} else {
		for (uint i = 0; i < mates.length(); ++i) {
			const float hv = (int(mates[i]) == ai.teamId) ? hMine : ai.ReadTeamValue(int(mates[i]), TV_SPR_HANDS, -1.f);
			hTeam += (hv >= 0.f) ? hv : hMine;
		}
	}
	gSprHandsUs = hTeam;
	array<int> keyF;
	for (uint s = 0; s < n; ++s) {
		gSprThOf[s] = -1.f;
		if ((gMsHeld[s] != 0) || !OnMap(gAllSpots[s]))
			continue;
		keyF.insertLast(int(gAllSpots[s].distance2D(box)) * 4096 + int(s));
	}
	keyF.sortAsc();
	gSprOpenAll = int(keyF.length());
	array<int> keyU;
	array<float> nearOf(n);
	float ySum = 0.f;
	for (uint r = 0; r < keyF.length(); ++r) {
		const int s = keyF[r] % 4096;
		const AIFloat3 p = gAllSpots[s];
		float tF = ((rate > 0.f) ? float(r) / rate : 1e6f) + p.distance2D(box) / ((vF > 1.f) ? vF : 1.f);
		for (uint i = 0; i < gSprFcP.length(); ++i) {
			const int d = gSprFcD[i];
			const float ts = gSprFcP[i].distance2D(p) / Catalog::gSpeed[d] + btMex / Catalog::gBuildPower[d];
			if (ts < tF)
				tF = ts;
		}
		gSprThOf[s] = tF;
		ySum += gAllSpotInc[s] * ext;
		float dn = -1.f;
		for (uint k = 0; k < bases.length(); ++k) {
			const float dk = bases[k].distance2D(p);
			if ((dn < 0.f) || (dk < dn))
				dn = dk;
		}
		nearOf[s] = dn;
		keyU.insertLast(int(dn) * 4096 + s);
	}
	gSprYMean = (keyF.length() > 0) ? ySum / float(keyF.length()) : 0.f;
	keyU.sortAsc();
	const float cyc0 = btMex / bp0 + gSprSpace / ((v0 > 1.f) ? v0 : 1.f);
	const float R = (cyc0 > 0.1f) ? hTeam / cyc0 : 0.f;
	gSprRUs = R;
	gSprIdxOf.resize(n);
	for (uint s = 0; s < n; ++s)
		gSprIdxOf[s] = -1;
	for (uint i = 0; i < gSprHist.length(); ++i)
		gSprHist[i] = 0;
	for (uint r = 0; r < keyU.length(); ++r) {
		const int s = keyU[r] % 4096;
		const float dh = gAllSpots[s].distance2D(home);
		const float t0 = ((R > 0.f) ? float(r) / R : 1e6f) + nearOf[s] / ((v0 > 1.f) ? v0 : 1.f);
		gSprIdxOf[s] = int(gSprS.length());
		gSprS.insertLast(s);
		gSprD.insertLast(dh);
		gSprTh.insertLast(gSprThOf[s]);
		gSprY.insertLast(gAllSpotInc[s] * ext);
		gSprT0.insertLast(t0);
		const float P = gSprThOf[s] / (t0 + gSprThOf[s]);
		int b = int(P * 5.f);
		b = (b < 0) ? 0 : ((b > 4) ? 4 : b);
		++gSprHist[b];
	}
	gSprHave = true;
}

void SprEnsure()
{
	if (ai.frame - gSprAt >= 5 * SECOND)
		SprRefresh();
}

// What one more hand of def `cd`, ready at tB, adds over the open spots; tFree is when it is done
// with the spots it took first and turns to generation.
float SpotRaceConM(int cd, float tB, float H, float tR, float hold0, float &out tFree, string &out terms)
{
	const double _t0 = ai.ClockUs();
	terms = "";
	tFree = tB;
	SprEnsure();
	const int mex = OpenRaceMex();
	const float vX = Catalog::gSpeed[cd];
	const float bpX = Catalog::gBuildPower[cd];
	if (!gSprHave || (mex <= 0) || (vX <= 1.f) || (bpX <= 0.f))
		return 0.f;
	const float btMex = Catalog::gBuildTime[mex];
	const float R = gSprRUs;
	const float cycX = btMex / bpX + gSprSpace / vX;
	const float rho = (cycX > 0.1f) ? 1.f / cycX : 0.f;
	float V = 0.f, took = 0.f, pSum = 0.f;
	for (uint i = 0; i < gSprS.length(); ++i) {
		const float r = float(i);
		const float t0 = gSprT0[i];
		float q1 = (R > 0.f) ? r / R : 1e6f;
		if ((R <= 0.f) || (r > R * tB))
			q1 = (r + rho * tB) / (R + rho);
		float t1 = q1 + gSprD[i] / vX;
		if (t1 < t0) {
			if ((R <= 0.f) || (r > R * tB))
				took += rho / (R + rho);
		} else {
			t1 = t0;
		}
		V += SprVal(gSprY[i], t1, gSprTh[i], H, tR, hold0) - SprVal(gSprY[i], t0, gSprTh[i], H, tR, hold0);
		pSum += gSprTh[i] / (t1 + gSprTh[i]);
	}
	tFree = tB + took * cycX;
	terms = " race(n=" + gSprS.length() + " took=" + NnF(took, 1) + " P=" + NnF((gSprS.length() > 0) ? pSum / float(gSprS.length()) : 0.f, 2)
		+ " rateF=" + NnF(gSprRate * 60.f, 1) + "/m)";
	gSprCostUs += float(ai.ClockUs() - _t0);
	++gSprCalls;
	return V;
}

// Open spot `s` held by the army: our con lands it, so P goes to one.
float SprHoldPrize(int s, float H, float tR, float hold0)
{
	if (!gSprHave || (s < 0) || (s >= int(gSprIdxOf.length())))
		return 0.f;
	const int i = gSprIdxOf[s];
	if (i < 0)
		return 0.f;
	const float t0 = gSprT0[i];
	if ((t0 >= H) || (gSprTh[i] >= H))
		return 0.f;
	const float P = gSprTh[i] / (t0 + gSprTh[i]);
	float den = H - ((t0 > gSprTh[i]) ? t0 : gSprTh[i]);
	den = (den > 0.f) ? den * (1.f - hold0) : 0.f;
	return gSprY[i] * (1.f - P) * (OrcSurv(t0, H, tR, hold0) + den);
}

// The open spots within r of p: what holding that ground is worth in the race.
float SprHoldPrizeNear(const AIFloat3& in p, float r)
{
	if (!SpotRaceOn())
		return 0.f;
	SprEnsure();
	if (!gSprHave)
		return 0.f;
	float H, tR, A, arrive, hold0;
	OpenRaceClock(0, H, tR, A, arrive, hold0);
	float v = 0.f;
	for (uint k = 0; k < gSprS.length(); ++k) {
		const int s = gSprS[k];
		if ((s >= 0) && (uint(s) < gAllSpots.length()) && (gAllSpots[s].distance2D(p) <= r))
			v += SprHoldPrize(s, H, tR, hold0);
	}
	return v;
}

// One of their constructors at `p`: its metal, and the claims its side loses while one walks out
// from their box to replace it.
float SprConPrize(int d, const AIFloat3& in p, float H)
{
	float v = Catalog::gCostM[d];
	if (!gSprHave || (gSprVF <= 1.f) || (gSprCycF <= 0.1f) || !OnMap(gSmhBox))
		return v;
	const float rebuild = p.distance2D(gSmhBox) / gSprVF;
	float claims = H / gSprCycF;
	const float perHand = (gSprHandsF > 0.f) ? float(gSprOpenAll) / gSprHandsF : 0.f;
	claims = (perHand < claims) ? perHand : claims;
	return v + claims * gSprYMean * rebuild;
}

// The team operation's contest targets beside their extractors: their cons, our contested spots.
void SprContestPick(float F, float teamM, float H, float cw, const AIFloat3& in cAt, int cDef)
{
	gSprKF = F;
	if (!SpotRaceOn())
		return;
	SprEnsure();
	if (!gSprHave)
		return;
	float tH, tR, A, arrive, hold0;
	OpenRaceClock(0, tH, tR, A, arrive, hold0);
	if (gSmhHasTgt && (gSprKind == 0))
		gSprKind = 1;
	const float reach = Military::HUNT_R + PUSH_STAND;
	for (uint i = 0; i < gSprFcP.length() + gSprS.length(); ++i) {
		AIFloat3 p;
		float prize = 0.f;
		int kind = 2;
		if (i < gSprFcP.length()) {
			p = gSprFcP[i];
			if (Catalog::gFlyer[gSprFcD[i]] || (p.distance2D(gSmhBox) < Builder::BASE_DANGER_DIST))
				continue;
			prize = SprConPrize(gSprFcD[i], p, H);
		} else {
			const uint k = i - gSprFcP.length();
			p = gAllSpots[gSprS[k]];
			prize = SprHoldPrize(gSprS[k], H, tR, hold0);
			kind = 3;
		}
		if (prize <= 0.f)
			continue;
		float E = aiMilitaryMgr.GetEnemyInflNear(p, reach);
		if ((cw > 0.f) && (cAt.distance2D(p) <= reach + Catalog::gMaxRange[cDef]))
			E += cw * Catalog::gPower[cDef];
		const float L = Military::NrLossFrac(E, F);
		const float net = prize * (1.f - L) - L * teamM;
		if ((net > 0.f) && (!gSmhHasTgt || (net > gSmhTgtNet))) {
			gSmhTgtNet = net;
			gSmhTgt = p;
			gSmhHasTgt = true;
			gSprKind = kind;
			gSprKE = E;
			gSprKPrize = prize;
		}
	}
	if (gSmhHasTgt)
		gSprKNet = gSmhTgtNet;
}

void SprPickBegin()
{
	gSprKind = 0;
	gSprKNet = 0.f;
	gSprKE = 0.f;
	gSprKPrize = 0.f;
}

// The launch bar while the team operation contests a target: its local need, unless the base ball
// is worth more per metal.
float SpotRaceBar(float want, float floorNow)
{
	if (!SpotRaceOn() || (TaPhase() == TA_NONE) || (int(ai.GetTeamBoard(BOARD_TA_KIND, 0.f)) != 5))
		return -1.f;
	// per metal of what each sends: the contest the group its local defence needs, the ball its own N,
	// worth only the part of the horizon left once it is gathered at our army rate
	const float teamM = Military::TeamArmyCost();
	const float mNeed = (gSprKF > 0.f) ? gSprKE * teamM / gSprKF : 0.f;
	float perM = 0.f;
	if (gSmhHasTgt)
		perM = (mNeed > 1.f) ? gSmhTgtNet / mNeed : 1e9f;
	float ballW = (EarlyBallOn() && (gEbBestStamp >= gEbStamp - 2) && (gEbBestDef > 0)) ? gEbBestW : 0.f;
	if (ballW > 0.f) {
		const float H = PayH();
		const float lack = gEbBestN * Catalog::gCostM[gEbBestDef] - gEbGatheredM;
		const float tBall = ((lack > 0.f) && (gEbRate > 0.01f)) ? lack / gEbRate : 0.f;
		ballW *= ((H > 1.f) && (tBall < H)) ? (H - tBall) / H : 0.f;
	}
	gSprBallW = ballW;
	gSprPerM = perM;
	if (ballW > perM) {
		++gSprBallN;
		return -1.f;
	}
	const float need = ai.GetTeamBoard(BOARD_TA_NEED, 0.f);
	const float bar = (need > floorNow) ? need : floorNow;
	++gSprBarN;
	gSprBarSum += bar;
	return bar;
}

// The commander's share of its time on extractors, as a hand in our queue (smallhard's job classes).
void SprNoteComJob(int c)
{
	gSprComMex = gSprComMex * 0.98f + ((c == 1) ? 0.02f : 0.f);
}

void SpotRaceNoteAsk(float rC, float rF, bool fighter)
{
	++gSprAsk;
	if (fighter)
		++gSprAskF;
	gSprRCSum += rC;
	gSprRFSum += rF;
}

void SpotRaceNoteOrder(int d)
{
	if (!Catalog::gMobile[d])
		return;
	if (Catalog::gBuilder[d]) {
		if (Catalog::gFlyer[d])
			++gSprOrdAir;
		else
			++gSprOrdCon;
	} else if (Catalog::gDps[d] > 0.f) {
		++gSprOrdFig;
	}
}

void SpotRaceNoteKill(float m, bool byUs)
{
	if (byUs)
		gSprKillM += m;
}

void SpotRaceNoteGo(float size, float need, bool raid)
{
	if (!SpotRaceOn())
		return;
	if (raid) {
		++gSprRaidN;
		gSprRaidSize = size;
		gSprRaidNeed = need;
	} else {
		++gSprGoN;
		gSprGoSize = size;
		gSprGoNeed = need;
	}
}

float SprIdleHomeM()
{
	float m = 0.f;
	for (uint i = 0; i < Military::gCombatId.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(Military::gCombatId[i]));
		if ((u is null) || (u.circuitDef is null) || u.circuitDef.IsAbleToFly())
			continue;
		IUnitTask@ t = u.task;
		if ((t is null) || (t.GetType() != Task::Type::FIGHTER)
			|| (t.GetFightType() != int(Task::FightType::DEFEND)))
			continue;
		m += Catalog::gCostM[int(u.circuitDef.id)];
	}
	return m;
}

void SpotRaceUpdate()
{
	if (!SpotRaceOn())
		return;
	const double _t0 = ai.ClockUs();
	SprEnsure();
	gSprCostUs += float(ai.ClockUs() - _t0);
	if (ai.frame < gSprLogAt)
		return;
	gSprLogAt = ai.frame + 60 * SECOND;
	int held = 0;
	for (uint i = 0; i < gLSpot.length(); ++i) {
		if (gLExtract[i] > 0.f)
			++held;
	}
	string hist = "";
	for (uint i = 0; i < gSprHist.length(); ++i)
		hist += ((i == 0) ? "" : "/") + gSprHist[i];
	AiLog(Factory::T() + "apex: spotrace-stat t=" + ai.teamId
		+ " open=" + gSprOpenAll + " mine=" + gSprS.length() + " P=" + hist
		+ " foeCons=" + gSprFcGN + "+" + gSprFcAN + "a hands=" + NnF(gSprHandsF, 1) + " rateF=" + NnF(gSprRate * 60.f, 1) + "/m"
		+ " held=" + held + " team=" + gMsOurs + " foe=" + gMsFoe
		+ " ask=" + gSprAsk + " fig=" + gSprAskF
		+ " rCon=" + NnF((gSprAsk > 0) ? gSprRCSum / float(gSprAsk) : 0.f, 2)
		+ " rFig=" + NnF((gSprAsk > 0) ? gSprRFSum / float(gSprAsk) : 0.f, 2)
		+ " ord=con" + gSprOrdCon + "/air" + gSprOrdAir + "/fig" + gSprOrdFig
		+ " tgt=" + SPR_KINDS[gSprKind] + " net=" + int(gSprKNet) + " prize=" + int(gSprKPrize) + " E=" + NnF(gSprKE, 1)
		+ " bar=" + gSprBarN + "/" + gSprBallN + "b@" + NnF((gSprBarN > 0) ? gSprBarSum / float(gSprBarN) : 0.f, 1)
		+ " perM=" + NnF((gSprPerM < 1e6f) ? gSprPerM : -1.f, 2) + " ballW=" + NnF(gSprBallW, 2)
		+ " go=" + gSprGoN + "@" + NnF(gSprGoSize, 1) + "/" + NnF(gSprGoNeed, 1)
		+ " raids=" + gSprRaidN + "@" + NnF(gSprRaidSize, 1) + "/" + NnF(gSprRaidNeed, 1)
		+ " killM=" + int(gSprKillM) + " idleHomeM=" + int(SprIdleHomeM())
		+ " calls=" + gSprCalls + " us=" + int(gSprCostUs));
	gSprAsk = 0;
	gSprAskF = 0;
	gSprRCSum = 0.f;
	gSprRFSum = 0.f;
	gSprOrdCon = 0;
	gSprOrdAir = 0;
	gSprOrdFig = 0;
	gSprBarN = 0;
	gSprBallN = 0;
	gSprBarSum = 0.f;
	gSprGoN = 0;
	gSprRaidN = 0;
	gSprKillM = 0.f;
	gSprCalls = 0;
	gSprCostUs = 0.f;
}

}  // namespace Market
