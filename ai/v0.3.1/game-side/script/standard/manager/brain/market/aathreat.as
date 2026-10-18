namespace Market {

// TUNE_AA_THREAT (docs/tunables.md): anti-air sized and sited by where their air hurts us.
// A place is ground where their armed air was seen over our buildings or killed something
// of ours; AA there is priced by what it stops at its catalog exchange rate against the
// aircraft we have seen.

const int AAT_SLOTS = 12;
bool gAatRead = false;
bool gAatOnV = false;
float gAatR = 0.f;
int gAatRTry = -1;
array<AIFloat3> gAatPos;
array<float> gAatHurtS;     // our buildings their air killed here, decayed metal
array<float> gAatHurtM;     // our mobile units their air killed here
array<float> gAatSeen;      // most of their armed air seen here at once, decayed
array<int> gAatLastS;       // frame of the last building lost to air here
array<int> gAatLastM;
array<int> gAatMobDef;      // the def of the last mobile unit of ours lost here
array<int> gAatHurtAt;      // first air damage of this episode
array<int> gAatAAAt;        // first AA standing here after it
array<float> gAatStake;
array<float> gAatMob;       // mobile AA here, in air metal it answers
array<float> gAatCover;     // static AA here, finished or manned, in air metal it answers
array<float> gAatCoverDone;
int gAatCoverAt = -1;
int gAatCoverStamp = -1;
bool gAatAnyManned = false;
int gAatAt = -1;
int gAatLogAt = 0;
float gAatAirNow = 0.f;
float gAatAirMem = 0.f;
float gAatRefQM = 0.f;
float gAatRefM = 0.f;
float gAatLossAir = 0.f;
float gAatLossAll = 0.f;
float gAatOrdS = 0.f;
float gAatOrdM = 0.f;
float gAatKillAir = 0.f;
float gAatGroundShort = 0.f;
int gAatShortCapN = 0;
float gAatOurAirFrac = 0.f;
float gAatShare = 0.f;
float gAatTradeS = 0.f;
float gAatTradeM = 0.f;
int gAatOurAirAt = -1;
int gAatPanicN = 0;
int gAatLabN = 0;
int gAatGuardN = 0;
int gAatPriceN = 0;
array<int> gAatGroundAA;
bool gAatGroundAAAt = false;
float gAatRefR2M = 0.f;     // their armed air's stand-off reach squared, metal-weighted
float gAatRaidHp = 0.f;     // the most strike air over our ground at once, or one that killed ours, decayed
float gAatRaidM = 0.f;
float gAatRaidSpd = 0.f;
array<float> gAatOff;

bool AatOn()
{
	if (!gAatRead) {
		gAatRead = true;
		gAatOnV = ai.GetTunable("apex_aa_threat", TUNE_AA_THREAT) > 0.f;
	}
	return gAatOnV;
}

// TUNE_AIR_ANSWER (docs/tunables.md)
int gAansOn = -1;
bool AirAnswerOn()
{
	if (gAansOn < 0)
		gAansOn = (ai.GetTunable("apex_air_answer", TUNE_AIR_ANSWER) > 0.f) ? 1 : 0;
	return gAansOn > 0;
}

// The reach an aircraft hits the ground from: none for what it drops or crashes onto its target.
float AatStandOff(int d)
{
	if (gAatOff.length() == 0) {
		gAatOff.resize(Catalog::gDefCount + 1);
		for (int i = 1; i <= Catalog::gDefCount; ++i) {
			const bool over = Catalog::gKamikaze[i] || Catalog::Def(i).IsRoleAny(Unit::Role::BOMBER.mask);
			gAatOff[i] = over ? 0.f : Catalog::gLandRange[i];
		}
	}
	return Catalog::ValidId(d) ? gAatOff[d] : 0.f;
}

float AatStandOffMean()
{
	return (gAatRefM > 1.f) ? sqrt(gAatRefR2M / gAatRefM) : 0.f;
}

// The share of their firing positions over a place that d, standing in it, reaches: they hit
// what stands within the place's radius from their own stand-off, so a tower they outrange
// shoots only at the planes that come closer.
float AatReach(int d)
{
	const float r = Catalog::gAirRange[d];
	if ((r <= 1.f) || (gAatRefM <= 1.f))
		return 1.f;
	const float rho = AatRadius();
	const float f = r * r / (rho * rho + gAatRefR2M / gAatRefM);
	return (f < 1.f) ? f : 1.f;
}

float AatRaidHp() { return gAatRaidHp; }
float AatRaidM() { return gAatRaidM; }
float AatRaidSpd() { return gAatRaidSpd; }
float AatLossAirRate() { return gAatLossAir / Military::BLEED_TAU; }

void AatNoteRaid(float hp, float m, float spd)
{
	if ((hp > gAatRaidHp) && (spd > 0.f)) {
		gAatRaidHp = hp;
		gAatRaidM = m;
		gAatRaidSpd = spd;
	}
}

float AatRadius()
{
	if (gAatR > 0.f)
		return gAatR;
	if ((gAatRTry >= 0) && (ai.frame < gAatRTry + 30 * SECOND))
		return 600.f;
	gAatRTry = ai.frame;
	float bestC = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || (ProtClassOf(d) != PROT_AA)
			|| (Catalog::gAirRange[d] <= 1.f))
			continue;
		const float c = TowerCostEq(d);
		if ((bestC <= 0.f) || (c < bestC)) {
			bestC = c;
			gAatR = Catalog::gAirRange[d];
		}
	}
	return (gAatR > 0.f) ? gAatR : 600.f;
}

// dps x hp per metal squared: the square law's strength per metal.
float AatQ(int d, bool vsAir)
{
	if (!Catalog::ValidId(d))
		return 0.f;
	const float c = TowerCostEq(d);
	const float t = Catalog::gAirT[d] + Catalog::gSurfT[d] + Catalog::gWaterT[d];
	if ((c <= 0.f) || (t <= 0.f))
		return 0.f;
	const float dps = Catalog::gSurfDpsOn ? (vsAir ? Catalog::gAirDps[d] : Catalog::gSurfDps[d])
			: Catalog::gDps[d] * (vsAir ? Catalog::gAirT[d] : Catalog::gSurfT[d]) / t;
	return dps * Catalog::gHealth[d] / (c * c);
}

// The metal of their aircraft one metal of `d` answers.
float AatTrade(int d)
{
	float q = AatQ(d, true);
	if (AirAnswerOn())
		q *= AatReach(d);
	const float ref = (gAatRefM > 1.f) ? (gAatRefQM / gAatRefM) : 0.f;
	if ((q <= 0.f) || (ref <= 0.f))
		return 1.f / AACoverFrac();
	return sqrt(q / ref);
}

float AatBestTrade(bool mobile)
{
	float best = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gFlyer[d] || (Catalog::gAirT[d] <= 0.01f))
			continue;
		if (mobile ? !AatGroundAADef(d) : (Catalog::gMobile[d] || (ProtClassOf(d) != PROT_AA)))
			continue;
		const float t = AatTrade(d);
		if (t > best)
			best = t;
	}
	return best;
}

bool AatGroundAADef(int d)
{
	return Catalog::ValidId(d) && Catalog::gAvailable[d] && Catalog::gMobile[d] && !Catalog::gFlyer[d]
		&& !Catalog::gBuilder[d] && (Catalog::gRole[d] == int(Unit::Role::AA.type));
}

int AatSlot(const AIFloat3& in at)
{
	const float r = AatRadius();
	int best = -1;
	float bestD = r;
	for (uint i = 0; i < gAatPos.length(); ++i) {
		const float dd = gAatPos[i].distance2D(at);
		if (dd < bestD) {
			bestD = dd;
			best = int(i);
		}
	}
	if (best >= 0)
		return best;
	if (int(gAatPos.length()) >= AAT_SLOTS) {
		float lowW = 0.f;
		for (uint i = 0; i < gAatPos.length(); ++i) {
			const float w = gAatHurtS[i] + gAatHurtM[i] + gAatSeen[i];
			if ((best < 0) || (w < lowW)) {
				lowW = w;
				best = int(i);
			}
		}
		AatDrop(uint(best));
	}
	gAatPos.insertLast(at);
	gAatHurtS.insertLast(0.f);
	gAatHurtM.insertLast(0.f);
	gAatSeen.insertLast(0.f);
	gAatLastS.insertLast(-1);
	gAatLastM.insertLast(-1);
	gAatMobDef.insertLast(-1);
	gAatHurtAt.insertLast(-1);
	gAatAAAt.insertLast(-1);
	gAatStake.insertLast(StakeAt(at, AatRadius()));
	gAatMob.insertLast(0.f);
	gAatCover.insertLast(0.f);
	gAatCoverDone.insertLast(0.f);
	gAatCoverAt = -1;
	return int(gAatPos.length()) - 1;
}

void AatDrop(uint i)
{
	gAatPos.removeAt(i);
	gAatHurtS.removeAt(i);
	gAatHurtM.removeAt(i);
	gAatSeen.removeAt(i);
	gAatLastS.removeAt(i);
	gAatLastM.removeAt(i);
	gAatMobDef.removeAt(i);
	gAatHurtAt.removeAt(i);
	gAatAAAt.removeAt(i);
	gAatStake.removeAt(i);
	gAatMob.removeAt(i);
	gAatCover.removeAt(i);
	gAatCoverDone.removeAt(i);
	gAatCoverAt = -1;
}

// Our finished unit killed by an identified enemy (main.as).
void AatNoteLoss(const AIFloat3& in at, const CCircuitDef@ mine, const CCircuitDef@ atk)
{
	if ((mine is null) || (atk is null) || (mine.costM <= 0.f))
		return;
	gAatLossAll += mine.costM;
	if (!atk.IsAbleToFly())
		return;
	gAatLossAir += mine.costM;
	const int s = AatSlot(at);
	if (mine.IsMobile()) {
		gAatHurtM[s] += mine.costM;
		gAatLastM[s] = ai.frame;
		gAatMobDef[s] = int(mine.id);
	} else {
		gAatHurtS[s] += mine.costM;
		gAatLastS[s] = ai.frame;
	}
	const int ad = int(atk.id);
	const float am = TowerCostEq(ad);
	const bool strikeGround = !mine.IsAbleToFly() && (Catalog::gSurfT[ad] > 0.01f);
	if (strikeGround)
		AatNoteRaid(Catalog::gHealth[ad], am, Catalog::gSpeed[ad]);
	if (strikeGround && AirAnswerOn()) {
		// what hurt us is their air as much as what we saw, and air that kills under the AA standing
		// here is air that AA did not answer
		const float off = AatStandOff(ad);
		gAatRefQM += AatQ(ad, false) * am;
		gAatRefM += am;
		gAatRefR2M += off * off * am;
		AatCoverRefresh();
		const float cov = gAatCover[s] + gAatMob[s];
		if ((cov > 0.f) && (gAatSeen[s] < cov + am))
			gAatSeen[s] = cov + am;
	}
	if (gAatSeen[s] < am)
		gAatSeen[s] = am;
	if (gAatHurtAt[s] < 0) {
		gAatHurtAt[s] = ai.frame;
		gAatAAAt[s] = -1;
	}
}

void AatNoteEnemyDeath(const CCircuitDef@ edef, bool byUs)
{
	if (byUs && (edef !is null) && edef.IsAbleToFly())
		gAatKillAir += edef.costM;
}

void AatNoteComOrder(int d)
{
	if (Catalog::ValidId(d) && (ProtClassOf(d) == PROT_AA))
		gAatOrdS += Catalog::gCostM[d];
}

void AatNotePend(const CCircuitDef@ d)
{
	if ((d !is null) && (Catalog::gRole[int(d.id)] == int(Unit::Role::AA.type)))
		gAatOrdM += d.costM;
}

bool AatRecent(int at)
{
	return (at >= 0) && (float(ai.frame - at) < Military::BLEED_TAU * float(SECOND));
}

// Where their air is hurting us now: the most air seen at a place where it killed something of
// ours inside the memory window, wherever that is (an ally's fighters fly there, not to our home).
float AatRaidNow(AIFloat3& out at)
{
	float best = 0.f;
	for (uint p = 0; p < gAatPos.length(); ++p) {
		if (!AatRecent(gAatLastS[p]) && !AatRecent(gAatLastM[p]))
			continue;
		if (gAatSeen[p] > best) {
			best = gAatSeen[p];
			at = gAatPos[p];
		}
	}
	return best;
}

// Static AA by place: finished, or ordered/framed with hands on it (an unmanned order is a
// placeholder, the async-sim-orders law). Recomputed when the ledger changes.
void AatCoverRefresh()
{
	if ((gAatCoverAt == ai.frame) && (gAatCoverStamp == gComStamp))
		return;
	gAatCoverAt = ai.frame;
	gAatCoverStamp = gComStamp;
	gAatAnyManned = false;
	const uint np = gAatPos.length();
	for (uint p = 0; p < np; ++p) {
		gAatCover[p] = 0.f;
		gAatCoverDone[p] = 0.f;
	}
	const float r = AatRadius();
	for (uint i = 0; i < ComLen(); ++i) {
		const int d = gComDef[i];
		if (ProtClassOf(d) != PROT_AA)
			continue;
		const bool done = (gComState[i] == CS_FINISHED);
		if (!done && ((gComTask[i] is null) || (Requests::Workers(gComTask[i]) == 0)))
			continue;
		gAatAnyManned = true;
		const float c = TowerCostEq(d) * AatTrade(d);
		for (uint p = 0; p < np; ++p) {
			if (gComPos[i].distance2D(gAatPos[p]) >= r)
				continue;
			gAatCover[p] += c;
			if (done)
				gAatCoverDone[p] += c;
		}
	}
}

// The best place for one more static AA of `d`: their air there not yet answered, times
// the rate it is costing us there (measured, or the stake at risk while it flies there).
bool AatStaticPrice(int d, AIFloat3& out at, float& out gain)
{
	gain = 0.f;
	if (gAatPos.length() == 0)
		return false;
	AatCoverRefresh();
	const float adds = TowerCostEq(d) * AatTrade(d);
	const float horiz = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
	const float anchor = 1.f / ((horiz > 1.f) ? horiz : 120.f);
	int best = -1;
	float bestStop = 0.f;
	bool bestSat = false;
	for (uint p = 0; p < gAatPos.length(); ++p) {
		const float seen = gAatSeen[p];
		if ((seen <= 0.f) || (gAatStake[p] <= 0.f))
			continue;
		const float cov = gAatCover[p] + gAatMob[p];
		float s0 = (seen - cov) / seen;
		s0 = (s0 > 0.f) ? s0 : 0.f;
		float s1 = (seen - cov - adds) / seen;
		s1 = (s1 > 0.f) ? s1 : 0.f;
		const float stopped = s0 - s1;
		if (stopped <= 0.f)
			continue;
		const float hurt = (gAatHurtS[p] + gAatHurtM[p]) / Military::BLEED_TAU;
		const float risk = gAatStake[p] * anchor * seen / (seen + cov);
		const float g = ((hurt > risk) ? hurt : risk) * stopped;
		if (g > gain) {
			gain = g;
			best = int(p);
			bestStop = stopped;
			bestSat = (s1 <= 0.f);
		}
	}
	if (best < 0)
		return false;
	at = gAatPos[best];
	++gAatPriceN;
	AansNoteStatic(d, at, bestStop, bestSat);
	return true;
}

// airanswer-stat: the AA defs priced since the last line, with the terms that ranked them.
array<int> gAnsDef;
array<float> gAnsV, gAnsG, gAnsC, gAnsSt;
array<int> gAnsAtX, gAnsAtZ, gAnsSat, gAnsWin, gAnsN;

int AansSlot(int d)
{
	for (uint i = 0; i < gAnsDef.length(); ++i) {
		if (gAnsDef[i] == d)
			return int(i);
	}
	gAnsDef.insertLast(d);
	gAnsV.insertLast(0.f);
	gAnsG.insertLast(0.f);
	gAnsC.insertLast(0.f);
	gAnsSt.insertLast(-1.f);
	gAnsAtX.insertLast(-1);
	gAnsAtZ.insertLast(-1);
	gAnsSat.insertLast(-1);
	gAnsWin.insertLast(0);
	gAnsN.insertLast(0);
	return int(gAnsDef.length()) - 1;
}

void AansNoteStatic(int d, const AIFloat3& in place, float stopped, bool sat)
{
	const int s = AansSlot(d);
	gAnsSt[s] = stopped;
	gAnsAtX[s] = int(place.x);
	gAnsAtZ[s] = int(place.z);
	gAnsSat[s] = sat ? 1 : 0;
}

void AansNoteAA(int d, float gain, float value, float cost)
{
	const int s = AansSlot(d);
	gAnsV[s] = value;
	gAnsG[s] = gain;
	gAnsC[s] = cost;
	++gAnsN[s];
}

void AansNoteWin(int d)
{
	++gAnsWin[AansSlot(d)];
}

string AansAAPart()
{
	string s = " off=" + int(AatStandOffMean()) + " rho=" + int(AatRadius()) + " aa=[";
	for (uint i = 0; i < gAnsDef.length(); ++i) {
		const int d = gAnsDef[i];
		if (i > 0)
			s += " ";
		s += Catalog::Def(d).GetName() + ":v" + NnF(gAnsV[i] * 1000.f, 3)
			+ "/g" + NnF(gAnsG[i], 2) + "/c" + int(gAnsC[i])
			+ "/tr" + NnF(AatTrade(d), 2) + "/re" + NnF(AatReach(d), 2)
			+ "/st" + NnF(gAnsSt[i], 2) + "/sat" + gAnsSat[i]
			+ "/at" + gAnsAtX[i] + "," + gAnsAtZ[i]
			+ "/n" + gAnsN[i] + "/top" + gAnsWin[i];
	}
	gAnsDef.resize(0);
	gAnsV.resize(0);
	gAnsG.resize(0);
	gAnsC.resize(0);
	gAnsSt.resize(0);
	gAnsAtX.resize(0);
	gAnsAtZ.resize(0);
	gAnsSat.resize(0);
	gAnsWin.resize(0);
	gAnsN.resize(0);
	return s + "]";
}

// Their air has seen us with nothing that shoots up, or a place where it killed a building
// in the memory window has no AA finished or manned within reach.
bool AatPanic()
{
	AatCoverRefresh();
	bool fire = (Military::AirSeenEver() > 0.f) && !gAatAnyManned;
	for (uint p = 0; !fire && (p < gAatPos.length()); ++p)
		fire = AatRecent(gAatLastS[p]) && (gAatCover[p] <= 0.f) && (gAatStake[p] > 0.f);
	if (fire)
		++gAatPanicN;
	return fire;
}

float AatPendGroundM()
{
	float m = 0.f;
	for (uint i = 0; i < Brain::gFQPendDef.length(); ++i) {
		const CCircuitDef@ d = Brain::gFQPendDef[i];
		if ((d !is null) && AatGroundAADef(int(d.id)))
			m += d.costM;
	}
	return m;
}

// Ground AA metal short of answering their air where it is killing our army.
float AatGroundShortM()
{
	if (gAatGroundShort <= 0.f)
		return 0.f;
	const float s = gAatGroundShort - AatPendGroundM();
	return (s > 0.f) ? s : 0.f;
}

// One ground AA unit from this lab while the army's places are short (production.as).
int AatLabOrder(const array<int>@ prods)
{
	if ((prods is null) || (AatGroundShortM() <= 0.f))
		return -1;
	int best = -1;
	float bestT = 0.f;
	for (uint i = 0; i < prods.length(); ++i) {
		const int d = prods[i];
		if (!AatGroundAADef(d))
			continue;
		const float t = AatTrade(d);
		if ((best < 0) || (t > bestT)) {
			best = d;
			bestT = t;
		}
	}
	if (best > 0)
		++gAatLabN;
	return best;
}

// A unit of ours where their air is killing the army and our AA there falls short.
CCircuitUnit@ AatGuardVip(CCircuitUnit@ aa)
{
	if ((aa is null) || (gAatPos.length() == 0))
		return null;
	AatCoverRefresh();
	const float r = AatRadius();
	for (int pass = 0; pass < int(AAT_SLOTS); ++pass) {
		int best = -1;
		float bestN = 0.f;
		for (uint p = 0; p < gAatPos.length(); ++p) {
			if ((gAatMobDef[p] < 0) || !AatRecent(gAatLastM[p]))
				continue;
			const float n = gAatSeen[p] - gAatCover[p] - gAatMob[p];
			if (n > bestN) {
				bestN = n;
				best = int(p);
			}
		}
		if (best < 0)
			return null;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(gAatMobDef[best]), gAatPos[best], r * 1.5f);
		for (uint i = 0; (us !is null) && (i < us.length()); ++i) {
			if ((us[i] !is null) && (us[i].id != aa.id) && !Military::JwLaunched(us[i])) {
				++gAatGuardN;
				return us[i];
			}
		}
		gAatMobDef[best] = -1;
	}
	return null;
}

// The anti-air row's weight per weight of the army and defence rows (budget.as): the share
// of the problem that is air, over what one metal of our AA answers of it.
float AatShareRatio()
{
	return gAatShare;
}

float AatShareCalc()
{
	float threat = gAatOurAirFrac;
	if (Military::AirSeenEver() > 0.f) {
		const float ground = Military::EnemyGroundCost();
		const float force = (gAatAirMem + ground > 1.f) ? gAatAirMem / (gAatAirMem + ground) : 0.f;
		const float loss = (gAatLossAll > 1.f) ? gAatLossAir / gAatLossAll : 0.f;
		threat = (force > loss) ? force : loss;
	}
	const float t = gAatTradeS;
	return (t > 0.f) ? threat / t : threat;
}

void AatOurAir()
{
	float air = 0.f;
	for (int d = 1; (d <= Catalog::gDefCount) && (d < int(gOwnCount.length())); ++d) {
		if ((gOwnCount[d] > 0) && Catalog::gFlyer[d] && !Catalog::gBuilder[d] && (Catalog::gSurfT[d] > 0.01f))
			air += float(gOwnCount[d]) * Catalog::gCostM[d];
	}
	const float army = ArmyValue();
	gAatOurAirFrac = (air + army > 1.f) ? air / (air + army) : 0.f;
}

void AatUpdate()
{
	const float dt = (gAatAt < 0) ? 0.f : float(ai.frame - gAatAt) / float(SECOND);
	gAatAt = ai.frame;
	float k = 1.f - dt / Military::BLEED_TAU;
	k = (k > 0.f) ? k : 0.f;
	gAatLossAir *= k;
	gAatLossAll *= k;
	gAatRefQM *= k;
	gAatRefM *= k;
	gAatRefR2M *= k;
	gAatRaidHp *= k;
	gAatRaidM *= k;
	for (uint p = 0; p < gAatPos.length(); ) {
		gAatHurtS[p] *= k;
		gAatHurtM[p] *= k;
		gAatSeen[p] *= k;
		if (gAatHurtS[p] + gAatHurtM[p] + gAatSeen[p] < 1.f)
			AatDrop(p);
		else
			++p;
	}
	const float r = AatRadius();
	float airNow = 0.f;
	const int n = aiEnemyMgr.GetEnemyGroupCount();
	for (int g = 0; g < n; ++g) {
		float airM = 0.f, airHp = 0.f, airSpd = 0.f;
		const int kc = aiEnemyMgr.GetEnemyGroupUnitCount(g);
		for (int i = 0; i < kc; ++i) {
			const int d = aiEnemyMgr.GetEnemyGroupUnitDef(g, i);
			if (!Catalog::ValidId(d) || !Catalog::gFlyer[d] || Catalog::gBuilder[d] || (Catalog::gSurfT[d] <= 0.01f))
				continue;
			const float m = TowerCostEq(d);
			const float off = AatStandOff(d);
			airM += m;
			airHp += Catalog::gHealth[d];
			airSpd += Catalog::gSpeed[d] * Catalog::gHealth[d];
			gAatRefQM += AatQ(d, false) * m;
			gAatRefM += m;
			gAatRefR2M += off * off * m;
		}
		if (airM <= 0.f)
			continue;
		airNow += airM;
		const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(g);
		if (StakeAt(gp, r) <= 0.f)
			continue;
		if (airHp > 0.f)
			AatNoteRaid(airHp, airM, airSpd / airHp);
		const int s = AatSlot(gp);
		if (gAatSeen[s] < airM)
			gAatSeen[s] = airM;
	}
	gAatAirNow = airNow;
	gAatAirMem = (gAatAirMem * k > airNow) ? gAatAirMem * k : airNow;
	if (!gAatGroundAAAt) {
		gAatGroundAAAt = true;
		for (int d = 1; d <= Catalog::gDefCount; ++d) {
			if (AatGroundAADef(d))
				gAatGroundAA.insertLast(d);
		}
	}
	gAatTradeS = AatBestTrade(false);
	gAatTradeM = AatBestTrade(true);
	const float tMob = gAatTradeM;
	if ((gAatOurAirAt < 0) || (ai.frame >= gAatOurAirAt + 30 * SECOND)) {
		gAatOurAirAt = ai.frame;
		AatOurAir();
	}
	gAatShare = AatShareCalc();
	gAatGroundShort = 0.f;
	gAatCoverAt = -1;
	AatCoverRefresh();
	for (uint p = 0; p < gAatPos.length(); ++p) {
		gAatStake[p] = StakeAt(gAatPos[p], r);
		gAatMob[p] = 0.f;
		for (uint q = 0; q < gAatGroundAA.length(); ++q) {
			const int d = gAatGroundAA[q];
			if ((d >= int(gOwnCount.length())) || (gOwnCount[d] <= 0))
				continue;
			array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(d), gAatPos[p], r);
			if (us !is null)
				gAatMob[p] += float(us.length()) * TowerCostEq(d) * AatTrade(d);
		}
		if ((gAatHurtAt[p] >= 0) && (gAatAAAt[p] < 0) && (gAatCoverDone[p] + gAatMob[p] > 0.f)) {
			gAatAAAt[p] = ai.frame;
			AiLog(Factory::T() + "apex: aathreat-aa t=" + ai.teamId + " at=" + int(gAatPos[p].x) + "," + int(gAatPos[p].z)
				+ " latS=" + int(float(gAatAAAt[p] - gAatHurtAt[p]) / float(SECOND))
				+ " static=" + int(gAatCoverDone[p]) + " mobile=" + int(gAatMob[p]));
		}
		if ((gAatMobDef[p] >= 0) && AatRecent(gAatLastM[p]) && (tMob > 0.f)) {
			const float need = gAatSeen[p] - gAatCover[p] - gAatMob[p];
			if (need > 0.f)
				gAatGroundShort += need / tMob;
		}
	}
	// THE WHOLE OF THEIR AIR IS THE MOST THERE IS TO ANSWER (his 10-17 online v0.3.0 game: mobile AA was 9-46% of
	// every seat's production, 361,000 m ordered against at most 56,108 m of their air seen, t14's short a median
	// 34,980 m). Each place counts only the mobile AA standing at it, and the AA walks off with the army, so every
	// place stayed short and the sum over twelve of them ran away. The places' sum may say where; it may not exceed
	// their remembered air less all our ground AA, wherever it stands, at the same exchange rate.
	if (tMob > 0.f) {
		float ownMob = 0.f;
		for (uint q = 0; q < gAatGroundAA.length(); ++q) {
			const int d = gAatGroundAA[q];
			if ((d < int(gOwnCount.length())) && (gOwnCount[d] > 0))
				ownMob += float(gOwnCount[d]) * TowerCostEq(d) * AatTrade(d);
		}
		float whole = (gAatAirMem - ownMob) / tMob;
		whole = (whole > 0.f) ? whole : 0.f;
		if (gAatGroundShort > whole) {
			gAatGroundShort = whole;
			++gAatShortCapN;
		}
	}
	if (ai.frame >= gAatLogAt) {
		gAatLogAt = ai.frame + 60 * SECOND;
		AatLog(tMob);
	}
}

void AatLog(float tMob)
{
	const double t0 = ai.ClockUs();
	string pl = "";
	int under = 0, withAA = 0, bare = 0;
	for (uint p = 0; p < gAatPos.length(); ++p) {
		const bool aa = (gAatCover[p] + gAatMob[p] > 0.f);
		++under;
		if (aa)
			++withAA;
		if (AatRecent(gAatLastS[p]) && (gAatCover[p] <= 0.f) && (gAatStake[p] > 0.f))
			++bare;
		const int lat = (gAatHurtAt[p] < 0) ? -1
				: int(float(((gAatAAAt[p] >= 0) ? gAatAAAt[p] : ai.frame) - gAatHurtAt[p]) / float(SECOND));
		pl += " " + int(gAatPos[p].x) + "," + int(gAatPos[p].z) + ":seen" + int(gAatSeen[p])
			+ "/hurt" + int(gAatHurtS[p]) + "+" + int(gAatHurtM[p]) + "/stake" + int(gAatStake[p])
			+ "/aa" + int(gAatCover[p]) + "+" + int(gAatMob[p])
			+ "/lat" + lat + ((gAatAAAt[p] >= 0) ? "" : "open");
	}
	const float force = (gAatAirMem + Military::EnemyGroundCost() > 1.f)
			? gAatAirMem / (gAatAirMem + Military::EnemyGroundCost()) : 0.f;
	AiLog(Factory::T() + "apex: aathreat-stat t=" + ai.teamId + " on=" + (AatOn() ? 1 : 0)
		+ " air=" + int(gAatAirNow) + "/" + int(gAatAirMem) + " fresh=" + int(aiEnemyMgr.GetEnemyCostFresh(RT::AIR))
		+ " force=" + NnF(force, 2) + " lossAir=" + NnF((gAatLossAll > 1.f) ? gAatLossAir / gAatLossAll : 0.f, 2)
		+ " ourAir=" + NnF(gAatOurAirFrac, 2)
		+ " trade=" + NnF(gAatTradeS, 2) + "/" + NnF(tMob, 2) + " ratio=" + NnF(gAatShare, 3)
		+ " share=" + NnF(Brain::TargetShare(Brain::AIRDEF), 3) + "/" + NnF(Brain::ShareOf(Brain::AIRDEF), 3)
		+ " ordered=" + int(gAatOrdS) + "/" + int(gAatOrdM)
		+ " killAir=" + int(gAatKillAir)
		+ " groundShort=" + int(AatGroundShortM()) + " shortCapped=" + gAatShortCapN
		+ " panic=" + gAatPanicN + " priced=" + gAatPriceN + " lab=" + gAatLabN + " guard=" + gAatGuardN
		+ " places=" + under + " withAA=" + withAA + " bare=" + bare + " manned=" + (gAatAnyManned ? 1 : 0)
		+ " r=" + int(AatRadius())
		+ " logUs=" + int(ai.ClockUs() - t0) + " |" + pl);
	gAatOrdS = 0.f;
	gAatOrdM = 0.f;
	gAatKillAir = 0.f;
	gAatPanicN = 0;
	gAatPriceN = 0;
	gAatLabN = 0;
	gAatGuardN = 0;
}

}  // namespace Market
