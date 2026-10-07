namespace Market {
//------------------------------------------------------------------------------
// THE COMMANDER'S SITUATION AND HIS ANSWER TO IT (his 2026-10-05: "We can't
// die, that's paramount. D-gun aggressively and make turrets to defend. Use
// the neural net to assess the situation and respond to it correctly").
//
// The threat is what can reach him before he can reach safety: every enemy
// ground group whose arrival (distance past its gun range over its fastest
// member) falls inside his walk to safety or the time one light tower takes
// him -- any tier, massed T1 included. The fight is read off the catalog's
// own dps and health, not UnitStrength (the commander's threat mod, and dps*hp
// summed linearly, rank him below a handful of T1).
// One body against many keeps full fire until it dies, so they fall one after
// another while their fire falls linearly to zero: he takes half their dps
// times the time he (with the guns and army beside him) needs to kill them,
// his share by health. His D-gun removes the kills its energy buys in that
// time, at the odds a sideways-moving unit leaves the beam.
//
// He fights a fight that leaves him COM_RETREAT_HEALTH of the health he
// brings (the bar at which the rules send him home anyway); a tower when it
// stands before they arrive and turns the fight; otherwise he leaves now.
// Recorded as `apex: nncom` for a commander net; the rule's pick carries ~all
// the weight and NO discovery game ever flattens it.
//------------------------------------------------------------------------------

const int COM_WORK = 0;
const int COM_FIGHT = 1;
const int COM_TURRET = 2;
const int COM_RETREAT = 3;
const int COM_N = 4;
const float COM_EPS = 0.01f;
const string NNC_COM = "hp,dgReady,dgShots,dgKills,foeHp,foeDps,foeTier,foeN,foeM,nearD,approach,"
	+ "arriveS,gunDps,armyDps,supHp,myDps,fightS,hpAfter,towerS,towersK,hpTower,safeD,safeS,homeD,"
	+ "horizonS,job,fwd,t2caution,hurtUnseen";

string ComOptName(int o)
{
	if (o == COM_WORK) return "WORK";
	if (o == COM_FIGHT) return "FIGHT";
	if (o == COM_TURRET) return "TURRET";
	if (o == COM_RETREAT) return "RETREAT";
	return "-";
}

// Our standing ground guns, rebuilt at most once a second.
array<AIFloat3> gCdTwPos;
array<float> gCdTwDps;
array<float> gCdTwHp;
array<float> gCdTwRng;
int gCdTwAt = -999999;
void ComTowersFill()
{
	if (ai.frame - gCdTwAt < SECOND)
		return;
	gCdTwAt = ai.frame;
	gCdTwPos.resize(0);
	gCdTwDps.resize(0);
	gCdTwHp.resize(0);
	gCdTwRng.resize(0);
	for (uint t = 0; t < gProtPos[PROT_DEF].length(); ++t) {
		const int d = (t < gProtDefId[PROT_DEF].length()) ? gProtDefId[PROT_DEF][t] : -1;
		if (!Catalog::ValidId(d) || (Catalog::gMaxRange[d] <= 0.f) || (Catalog::gSurfT[d] <= 0.f))
			continue;
		gCdTwPos.insertLast(gProtPos[PROT_DEF][t]);
		gCdTwDps.insertLast(Catalog::gDps[d]);
		gCdTwHp.insertLast(Catalog::gHealth[d]);
		gCdTwRng.insertLast(Catalog::gMaxRange[d]);
	}
}

// Our guns whose range covers `p`.
void ComGunAt(const AIFloat3& in p, float& out dps, float& out hp)
{
	ComTowersFill();
	dps = 0.f;
	hp = 0.f;
	for (uint i = 0; i < gCdTwPos.length(); ++i) {
		if (gCdTwPos[i].distance2D(p) <= gCdTwRng[i]) {
			dps += gCdTwDps[i];
			hp += gCdTwHp[i];
		}
	}
}

// Our mobile ground army within r of p.
void ComArmyAt(const AIFloat3& in p, float r, float& out dps, float& out hp)
{
	dps = 0.f;
	hp = 0.f;
	for (uint i = 0; i < Military::gCombatId.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(Military::gCombatId[i]));
		if ((u is null) || (u.circuitDef is null) || u.circuitDef.IsAbleToFly())
			continue;
		if (u.GetPos(ai.frame).distance2D(p) > r)
			continue;
		const int d = int(u.circuitDef.id);
		dps += Catalog::gDps[d];
		hp += Catalog::gHealth[d] * u.GetHealthPercent();
	}
}

// THE D-GUN IN THE FIGHT: the shots its energy and reload allow in `tFight`,
// each landing with the chance the beam's width leaves a unit moving sideways
// at their speed through the flight (the engine leads the target; a turning
// raider still slips). Kills, at most the n that come inside its range.
float ComDGunKills(CCircuitUnit@ u, float tFight, float foeSpd, float foeR, int n)
{
	const float cost = u.DGunCostE();
	if ((cost <= 0.f) || (n <= 0) || (tFight <= 0.f))
		return 0.f;
	const float eNet = Eco::EInc() - Eco::EPull();
	float shots = floor(Eco::ECur() / cost);
	if (eNet > 0.f)
		shots += floor(eNet * tFight / cost);
	const float rl = u.DGunReload();
	if (rl > 0.f) {
		const float byReload = floor(tFight / rl) + 1.f;
		shots = (byReload < shots) ? byReload : shots;
	}
	const float pSpd = u.DGunSpeed();
	const float rng = u.DGunRange();
	float hit = 1.f;
	if ((pSpd > 0.f) && (foeSpd > 0.f)) {
		// half range on average, the sideways share of a random heading 2/pi
		const float slip = foeSpd * 0.6366f * (0.5f * rng / pSpd);
		const float reach = u.DGunAoe() + foeR;
		if (slip > reach)
			hit = reach / slip;
	}
	const float k = shots * hit;
	return (k > float(n)) ? float(n) : k;
}

// His health share after the fight (0 if he cannot kill them), and the
// seconds it takes.
float ComFightHpAfter(float hp, float hpMax, float myDps, float supDps, float supHp,
		float foeDps, float foeHp, float kills, int n, float& out secs)
{
	secs = 0.f;
	if ((n <= 0) || (foeHp <= 0.f))
		return hp;
	const float keep = 1.f - kills / float(n);
	const float fHp = foeHp * keep;
	const float fDps = foeDps * keep;
	const float ours = myDps + supDps;
	if (ours <= 0.f)
		return 0.f;
	secs = fHp / ours;
	const float mine = hpMax * hp;
	const float share = (mine + supHp > 0.f) ? mine / (mine + supHp) : 1.f;
	const float after = hp - 0.5f * fDps * secs * share / ((hpMax > 1.f) ? hpMax : 1.f);
	return (after > 0.f) ? after : 0.f;
}

bool ComWins(float hp, float after)
{
	return after >= COM_RETREAT_HEALTH * hp;
}

// The assessment, cached per frame.
int gCsAt = -1;
bool gCsThreat = false;
bool gCsWin = false;
bool gCsDgReady = false;
bool gCsT2 = false;
int gCsTier = 0;
int gCsN = 0;
int gCsJob = -1;
int gCsRule = COM_WORK;
int gCsTowersK = 0;
float gCsHp = 1.f;
float gCsMyDps = 0.f;
float gCsFoeHp = 0.f;
float gCsFoeM = 0.f;
float gCsFoeDps = 0.f;
float gCsFoeSpd = 0.f;
float gCsNearD = -1.f;
float gCsApp = 0.f;
float gCsArrive = -1.f;
float gCsGunDps = 0.f;
float gCsArmyDps = 0.f;
float gCsSupHp = 0.f;
float gCsFightS = 0.f;
float gCsHpAfter = 1.f;
float gCsHpTower = 0.f;
float gCsShots = 0.f;
float gCsKills = 0.f;
float gCsTowerS = 0.f;
float gCsSafeD = 0.f;
float gCsSafeS = 0.f;
float gCsHomeD = -1.f;
float gCsHorizon = 0.f;
float gCsFwd = 0.f;
float gCsHpPrev = 1.f;
int gCsHpPrevAt = -1;
bool gCsHurtUnseen = false;
AIFloat3 gCsSafe;
AIFloat3 gCsFoeAt;
AIFloat3 gCsHere;

// Where he withdraws to: the back of our base (the farm, else home), or a
// nearer stand of our guns, not toward the threat, where he would win.
AIFloat3 ComSafePoint(const AIFloat3& in here, const AIFloat3& in foe, bool haveFoe,
		CCircuitUnit@ u, float foeDps, float foeHp, int n, float& out walk)
{
	ComTowersFill();
	AIFloat3 best = RetirePos();
	if (!OnMap(best))
		best = here;
	float bestD = here.distance2D(best);
	const float hereFoe = haveFoe ? here.distance2D(foe) : 0.f;
	const int cd = int(u.circuitDef.id);
	const float hp = u.GetHealthPercent();
	for (uint i = 0; i < gCdTwPos.length(); ++i) {
		const AIFloat3 c = gCdTwPos[i];
		const float d = here.distance2D(c);
		if ((d >= bestD) || (haveFoe && (c.distance2D(foe) < hereFoe) && (d > gCdTwRng[i])))
			continue;
		float gd = 0.f, gh = 0.f, s = 0.f;
		ComGunAt(c, gd, gh);
		if (ComWins(hp, ComFightHpAfter(hp, Catalog::gHealth[cd], Catalog::gDps[cd], gd, gh,
				foeDps, foeHp, 0.f, n, s)))
		{
			best = c;
			bestD = d;
		}
	}
	walk = bestD;
	return best;
}

AIFloat3 gComJobPos;
int gComJobAt = -999999;
int ComJobKind(CCircuitUnit@ u)
{
	IUnitTask@ t = u.task;
	if (t is null)
		return -1;
	if (t.GetType() == Task::Type::BUILDER) {
		const int bt = int(t.GetBuildType());
		if ((bt != int(Task::BuildType::DEFENCE)) && (bt != int(Task::BuildType::PATROL))
			&& OnMap(t.GetBuildPos()))
		{
			gComJobPos = t.GetBuildPos();
			gComJobAt = ai.frame;
		}
		return bt;
	}
	return 100 + int(t.GetType());
}

// Where his self-tower stands: by the job he was on (his mex, his site) when
// that is still beside him, else where he is.
AIFloat3 ComGunAnchor(const AIFloat3& in here)
{
	if ((ai.frame - gComJobAt < 30 * SECOND) && (gComJobPos.distance2D(here) < HERE_R))
		return gComJobPos;
	return here;
}

int ComTowersK() { return gCsTowersK; }
AIFloat3 ComFoeAt() { return gCsThreat ? gCsFoeAt : AIFloat3(-1.f, 0.f, -1.f); }
float ComFoeM() { return gCsFoeM; }

void ComAssess(CCircuitUnit@ u)
{
	if (gCsAt == ai.frame)
		return;
	gCsAt = ai.frame;
	const int cd = int(u.circuitDef.id);
	const AIFloat3 here = u.GetPos(ai.frame);
	gCsHere = here;
	gCsHp = u.GetHealthPercent();
	gCsHurtUnseen = (gCsHpPrevAt >= 0) && (gCsHp < gCsHpPrev - 0.005f);
	gCsHpPrev = gCsHp;
	gCsHpPrevAt = ai.frame;
	gCsMyDps = Catalog::gDps[cd];
	const float hpMax = Catalog::gHealth[cd];
	gCsT2 = Factory::gHaveT2 || CommCaution(u);
	gCsJob = ComJobKind(u);
	gCsFwd = Military::ForwardFraction(here);
	gCsHomeD = Builder::gHomeSet ? here.distance2D(Builder::gHomePos) : -1.f;
	gCsDgReady = u.DGunReady(ai.frame, Eco::ECur());
	const float spd = (Catalog::gSpeed[cd] > 1.f) ? Catalog::gSpeed[cd] : 1.f;
	const float dgR = u.DGunRange();
	CCircuitDef@ light = SideDef3("armllt", "corllt", "leglht");
	const int ld = (light is null) ? -1 : int(light.id);
	const float bp = Catalog::gBuildPower[cd];
	gCsTowerS = ((ld > 0) && (bp > 0.f)) ? Catalog::gBuildTime[ld] / bp : 1e6f;

	// The groups first; the safe point needs where they are, the horizon the
	// safe point.
	const int nG = aiEnemyMgr.GetEnemyGroupCount();
	array<int> gi2;
	array<float> gArr, gHp, gDps, gSpd, gD, gApp, gCost, gR;
	array<int> gTier, gN, gNc;
	float nearAll = -1.f;
	AIFloat3 nearAt;
	float allDps = 0.f, allHp = 0.f;
	int allN = 0;
	for (int gi = 0; gi < nG; ++gi) {
		const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(gi);
		if (!OnMap(gp))
			continue;
		int tier = 0, nMob = 0, nCl = 0;
		float vmax = 0.f, dps = 0.f, hpS = 0.f, rad = 0.f;
		const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(gi);
		for (int k = 0; k < nU; ++k) {
			const int d = aiEnemyMgr.GetEnemyGroupUnitDef(gi, k);
			if (!Catalog::ValidId(d) || !Catalog::gMobile[d] || Catalog::gFlyer[d]
				|| (Catalog::gSurfT[d] <= 0.f) || (Catalog::gDps[d] <= 0.f))
				continue;
			++nMob;
			if (Catalog::gMaxRange[d] <= dgR)
				++nCl;
			dps += Catalog::gDps[d];
			hpS += Catalog::gHealth[d];
			rad += 4.f * float((Catalog::gFootX[d] > Catalog::gFootZ[d]) ? Catalog::gFootX[d] : Catalog::gFootZ[d]);
			if (Catalog::gSpeed[d] > vmax)
				vmax = Catalog::gSpeed[d];
			const int t = DefTier(d);
			if (t > tier)
				tier = t;
		}
		if ((nMob == 0) || (vmax <= 0.f))
			continue;
		const float dd = gp.distance2D(here);
		const float rng = aiEnemyMgr.GetEnemyGroupRange(gi);
		const AIFloat3 vv = aiEnemyMgr.GetEnemyGroupVelVec(gi);
		AIFloat3 toMe = here - gp;
		toMe.SafeNormalize2D();
		const float app = vv.x * toMe.x + vv.z * toMe.z;
		const float arr = (dd > rng) ? (dd - rng) / vmax : 0.f;
		// a group walking away is let go, unless it is already on him
		if ((app < -1.f) && (arr > 0.f))
			continue;
		gi2.insertLast(gi);
		gArr.insertLast(arr);
		gHp.insertLast(hpS);
		gDps.insertLast(dps);
		gSpd.insertLast(vmax);
		gD.insertLast(dd);
		gApp.insertLast(app);
		gCost.insertLast(aiEnemyMgr.GetEnemyGroupCost(gi));
		gR.insertLast(rad / float(nMob));
		gTier.insertLast(tier);
		gN.insertLast(nMob);
		gNc.insertLast(nCl);
		allDps += dps;
		allHp += hpS;
		allN += nMob;
		if ((nearAll < 0.f) || (dd < nearAll)) {
			nearAll = dd;
			nearAt = gp;
		}
	}
	float walk = 0.f;
	gCsSafe = ComSafePoint(here, nearAt, nearAll >= 0.f, u, allDps, allHp, allN, walk);
	gCsSafeD = walk;
	gCsSafeS = walk / spd;
	gCsHorizon = (gCsSafeS > gCsTowerS) ? gCsSafeS : gCsTowerS;
	gCsFoeHp = 0.f; gCsFoeM = 0.f; gCsFoeDps = 0.f; gCsFoeSpd = 0.f;
	gCsTier = 0; gCsN = 0; gCsNearD = -1.f; gCsApp = 0.f; gCsArrive = -1.f;
	int nClose = 0;
	float rSum = 0.f;
	for (uint i = 0; i < gi2.length(); ++i) {
		if (gArr[i] > gCsHorizon)
			continue;
		gCsFoeHp += gHp[i];
		gCsFoeM += gCost[i];
		gCsFoeDps += gDps[i];
		gCsN += gN[i];
		nClose += gNc[i];
		rSum += gR[i] * float(gN[i]);
		if (gSpd[i] > gCsFoeSpd)
			gCsFoeSpd = gSpd[i];
		if (gTier[i] > gCsTier)
			gCsTier = gTier[i];
		if ((gCsArrive < 0.f) || (gArr[i] < gCsArrive))
			gCsArrive = gArr[i];
		if ((gCsNearD < 0.f) || (gD[i] < gCsNearD)) {
			gCsNearD = gD[i];
			gCsApp = gApp[i];
			gCsFoeAt = aiEnemyMgr.GetEnemyGroupPos(gi2[i]);
		}
	}
	gCsThreat = gCsN > 0;
	const float r = ai.GetTunable("apex_threat_r", TUNE_THREAT_R);
	float gh = 0.f, ah = 0.f;
	ComGunAt(here, gCsGunDps, gh);
	ComArmyAt(here, r, gCsArmyDps, ah);
	gCsSupHp = gh + ah;
	gCsShots = 0.f;
	gCsKills = 0.f;
	gCsFightS = 0.f;
	gCsHpAfter = gCsHp;
	gCsHpTower = 0.f;
	gCsTowersK = 0;
	gCsWin = true;
	if (!gCsThreat) {
		// Losing health with nothing seen is an attacker under the fog.
		gCsRule = gCsHurtUnseen ? COM_RETREAT : COM_WORK;
		return;
	}
	const float cost = u.DGunCostE();
	if (cost > 0.f)
		gCsShots = floor(Eco::ECur() / cost);
	// The D-gun's window is the fight without it.
	float t0 = 0.f;
	ComFightHpAfter(gCsHp, hpMax, gCsMyDps, gCsGunDps + gCsArmyDps, gCsSupHp,
			gCsFoeDps, gCsFoeHp, 0.f, gCsN, t0);
	gCsKills = ComDGunKills(u, t0, gCsFoeSpd, rSum / float(gCsN), nClose);
	gCsHpAfter = ComFightHpAfter(gCsHp, hpMax, gCsMyDps, gCsGunDps + gCsArmyDps, gCsSupHp,
			gCsFoeDps, gCsFoeHp, gCsKills, gCsN, gCsFightS);
	// Hurt, he takes no fight at all: the rules already send him home there.
	gCsWin = ComWins(gCsHp, gCsHpAfter) && (gCsHp >= COM_RETREAT_HEALTH);
	// Towers he can stand before the first of them arrives, as far as the bank
	// and income pay for them.
	if ((ld > 0) && !gCsT2 && (gCsTowerS < 1e5f) && (gCsArrive >= gCsTowerS)) {
		int k = int(floor(gCsArrive / gCsTowerS));
		const float cm = Catalog::gCostM[ld], ce = Catalog::gCostE[ld];
		int afford = 99;
		if (cm > 0.f)
			afford = int(floor((Eco::MCur() + Eco::MInc() * gCsArrive) / cm));
		if (ce > 0.f) {
			const int ea = int(floor((Eco::ECur() + Eco::EInc() * gCsArrive) / ce));
			afford = (ea < afford) ? ea : afford;
		}
		k = (afford < k) ? afford : k;
		if (k > 0) {
			gCsTowersK = k;
			float s = 0.f;
			gCsHpTower = ComFightHpAfter(gCsHp, hpMax, gCsMyDps,
					gCsGunDps + gCsArmyDps + float(k) * Catalog::gDps[ld],
					gCsSupHp + float(k) * Catalog::gHealth[ld],
					gCsFoeDps, gCsFoeHp, gCsKills, gCsN, s);
		}
	}
	if (gCsT2 && ComFar(here))
		gCsRule = COM_RETREAT;
	else if (gCsWin)
		gCsRule = (gCsArrive <= gCsTowerS) ? COM_FIGHT : COM_WORK;
	else if (ComWins(gCsHp, gCsHpTower))
		gCsRule = COM_TURRET;
	else
		gCsRule = COM_RETREAT;
}

void ComFields(array<float>& out f)
{
	f.resize(0);
	f.insertLast(gCsHp);
	f.insertLast(gCsDgReady ? 1.f : 0.f);
	f.insertLast(gCsShots);
	f.insertLast(gCsKills);
	f.insertLast(gCsFoeHp);
	f.insertLast(gCsFoeDps);
	f.insertLast(float(gCsTier));
	f.insertLast(float(gCsN));
	f.insertLast(gCsFoeM);
	f.insertLast(gCsNearD);
	f.insertLast(gCsApp);
	f.insertLast(gCsArrive);
	f.insertLast(gCsGunDps);
	f.insertLast(gCsArmyDps);
	f.insertLast(gCsSupHp);
	f.insertLast(gCsMyDps);
	f.insertLast(gCsFightS);
	f.insertLast(gCsHpAfter);
	f.insertLast(gCsTowerS);
	f.insertLast(float(gCsTowersK));
	f.insertLast(gCsHpTower);
	f.insertLast(gCsSafeD);
	f.insertLast(gCsSafeS);
	f.insertLast(gCsHomeD);
	f.insertLast(gCsHorizon);
	f.insertLast(float(gCsJob));
	f.insertLast(gCsFwd);
	f.insertLast(gCsT2 ? 1.f : 0.f);
	f.insertLast(gCsHurtUnseen ? 1.f : 0.f);
}

// THE COMMANDER NET'S HOOK: scores each option from the state and the
// commander fields and moves the weights in log space by the trust it has
// earned. A stub until the trainer writes NNC_* -- trust 0, rules alone.
float NnComScore(const array<float>& in st, const array<float>& in com, array<float>& w)
{
	return NnHeadScore(NNC_ON, NNC_STATE, NNC_COM, NNC_S, NNC_O, NNC_H, NNC_XM, NNC_XS, NNC_W1,
		NNC_B1, NNC_W2, NNC_B2, NNC_WO, NNC_BO, NNC_TRUST, st, com, w);
}

int gComDec = COM_WORK;       // the decision in force
float gComFlat = -1.f;        // discovery games: chance a decision goes safer, rolled once
int gComExpUntil = -1, gComExpPick = -1, gComExpN = 0, gComExpNext = 0;
int gComDecAt = -999999;
int gComNextAt = -1;
int gComAssessAt = -1;
bool gComHeader = false;
int gComDecN = 0;
array<int> gComChosenN(COM_N, 0);
array<int> gComRuleN(COM_N, 0);
array<int> gComEffF(COM_N, 0);
int gComTickAt = -1;
int gComWithdrawN = 0;
int gComDropN = 0;
int gComDropAt = -999999;
int gComStatAt = 0;
double gComUsSum = 0.0;
double gComUsMax = 0.0;
// the turret episode, for its outcome line
int gComTurAt = -1;
float gComTurHp = 0.f;
float gComTurFoe = 0.f;
float gComTurGun = 0.f;
int gComTurN = 0;
int gComTurHeld = 0;

int ComDecision() { return gComDec; }
bool ComRetreating() { return gComDec == COM_RETREAT; }
bool ComTurreting() { return gComDec == COM_TURRET; }

string ComSitText()
{
	return "hp=" + int(gCsHp * 100.f) + " after=" + int(gCsHpAfter * 100.f)
		+ " foe=" + int(gCsFoeM) + "m/T" + gCsTier + "x" + gCsN
		+ " dps=" + int(gCsFoeDps) + "/hp=" + int(gCsFoeHp)
		+ " vs dps=" + int(gCsMyDps) + "+" + int(gCsGunDps + gCsArmyDps)
		+ " fight=" + formatFloat(gCsFightS, "", 0, 1) + "s"
		+ " near=" + int(gCsNearD) + " arrive=" + formatFloat(gCsArrive, "", 0, 1) + "s"
		+ " safe=" + int(gCsSafeD) + "/" + formatFloat(gCsSafeS, "", 0, 1) + "s"
		+ " dg=" + (gCsDgReady ? 1 : 0) + "/" + formatFloat(gCsKills, "", 0, 1)
		+ " fwd=" + formatFloat(gCsFwd, "", 0, 2) + " t2=" + (gCsT2 ? 1 : 0)
		+ " unseen=" + (gCsHurtUnseen ? 1 : 0);
}

void ComDecide(CCircuitUnit@ u, const string& in why)
{
	const double t0 = ai.ClockUs();
	array<float> com;
	ComFields(com);
	array<float> st;
	NnState(null, st);
	const int rule = gCsRule;
	array<float> w(COM_N);
	// The floor lets the net pick another option; it never draws him out of a
	// retreat (789 RETREAT->WORK in a day were this floor, not the net).
	for (int o = 0; o < COM_N; ++o)
		w[o] = (o == rule) ? 1.f : ((rule == COM_RETREAT) ? 0.f : COM_EPS);
	const float trust = NnComScore(st, com, w);
	float sum = 0.f;
	for (int o = 0; o < COM_N; ++o)
		sum += w[o];
	array<float> p(COM_N);
	for (int o = 0; o < COM_N; ++o)
		p[o] = (trust > 0.f) ? w[o] / sum : ((o == rule) ? 1.f : 0.f);
	int chosen = rule;
	// Discovery only ever toward SAFER: work or fight may become a turret or a
	// retreat, a turret a retreat -- held 15 s so what followed is its doing.
	// Nothing ever explores him into a fight the rule would leave.
	const bool explore = gNnExploreRolled && gNnExplore;
	if (explore && (gComFlat < 0.f))
		gComFlat = float(AiRandom(0, 10000)) / 10000.f * 0.3f;
	if (explore && (rule != COM_RETREAT) && (ai.frame < gComExpUntil) && (gComExpPick > rule))
		chosen = gComExpPick;
	else if (explore && (rule != COM_RETREAT) && (ai.frame >= gComExpNext)
		&& (float(AiRandom(0, 10000)) / 10000.f < gComFlat)) {
		chosen = ((rule < COM_TURRET) && (gCsTowersK > 0) && (AiRandom(0, 1) == 0)) ? COM_TURRET : COM_RETREAT;
		gComExpPick = chosen;
		gComExpUntil = ai.frame + 15 * SECOND;
		// he decides every second under threat: one trial a minute at most
		gComExpNext = ai.frame + 60 * SECOND;
		++gComExpN;
	} else if (trust > 0.f) {
		const float r = float(AiRandom(0, 10000)) / 10000.f;
		float acc = 0.f;
		chosen = COM_N - 1;
		for (int o = 0; o < COM_N; ++o) {
			acc += p[o];
			if (r < acc) {
				chosen = o;
				break;
			}
		}
	}
	const int was = gComDec;
	gComDec = chosen;
	gComDecAt = ai.frame;
	++gComDecN;
	++gComChosenN[chosen];
	++gComRuleN[rule];
	if (!gComHeader) {
		gComHeader = true;
		AiLog("apex: nncom-schema v1 state=" + NN_STATE + " com=" + NNC_COM
			+ " opt=name,w,p opts=WORK,FIGHT,TURRET,RETREAT");
	}
	string ln = "apex: nncom t=" + ai.teamId + " f=" + ai.frame + " why=" + why
		+ " rule=" + ComOptName(rule) + " ex=" + (explore ? 1 : 0) + " trust=" + NnF(trust, 2) + " |";
	for (uint k = 0; k < st.length(); ++k)
		ln += ((k == 0) ? " " : ",") + NnF(st[k], 2);
	ln += " |";
	for (uint k = 0; k < com.length(); ++k)
		ln += ((k == 0) ? " " : ",") + NnF(com[k], 3);
	for (int o = 0; o < COM_N; ++o)
		ln += ((o == 0) ? " | " : " ; ") + ComOptName(o) + "," + NnF(w[o], 4) + "," + NnF(p[o], 6);
	ln += " | chosen=" + chosen;
	AiLog(ln);
	if ((chosen == COM_RETREAT) && (was != COM_RETREAT)) {
		++gComWithdrawN;
		AiLog(Factory::T() + "apex: com-withdraw t=" + ai.teamId + " " + ComSitText());
	}
	if ((chosen == COM_TURRET) && (was != COM_TURRET)) {
		gComTurAt = ai.frame;
		gComTurHp = gCsHp;
		gComTurFoe = gCsFoeHp;
		gComTurGun = gCsGunDps;
		++gComTurN;
		AiLog(Factory::T() + "apex: com-turret t=" + ai.teamId + " k=" + gCsTowersK
			+ " hpTower=" + int(gCsHpTower * 100.f) + " " + ComSitText());
	} else if ((chosen != COM_TURRET) && (was == COM_TURRET) && (gComTurAt >= 0)) {
		if (gCsGunDps > gComTurGun)
			++gComTurHeld;
		AiLog(Factory::T() + "apex: com-turret-end t=" + ai.teamId
			+ " secs=" + ((ai.frame - gComTurAt) / SECOND) + " next=" + ComOptName(chosen)
			+ " hp=" + int(gComTurHp * 100.f) + "->" + int(gCsHp * 100.f)
			+ " gunDps=" + int(gComTurGun) + "->" + int(gCsGunDps)
			+ " foeHp=" + int(gComTurFoe) + "->" + int(gCsFoeHp));
		gComTurAt = -1;
	}
	const double us = ai.ClockUs() - t0;
	gComUsSum += us;
	if (us > gComUsMax)
		gComUsMax = us;
}

// Once a second from CommWatch. Assessed every second while anything is in
// his horizon, every five otherwise; decided when the rule's pick changes, every
// three seconds under threat, every thirty in peace.
void ComDecideTick(CCircuitUnit@ u)
{
	if ((u is null) || (u.circuitDef is null) || !CommRules() || (u.GetHealthPercent() <= 0.f))
		return;
	if (gComTickAt >= 0)
		gComEffF[gComDec] += ai.frame - gComTickAt;
	gComTickAt = ai.frame;
	const bool hot = gCsThreat || (gComDec != COM_WORK);
	if ((gComAssessAt >= 0) && (ai.frame - gComAssessAt < (hot ? SECOND : 5 * SECOND)))
		return;
	gComAssessAt = ai.frame;
	ComAssess(u);
	// A tower the executor would refuse (interior ground, broke, already
	// covered) is no plan: then the fight is lost and he leaves.
	if (gCsRule == COM_TURRET) {
		const int was = gComDec;
		gComDec = COM_TURRET;
		const bool can = ComSelfGun(u, false) !is null;
		gComDec = was;
		if (!can)
			gCsRule = COM_RETREAT;
	}
	if (gComNextAt < 0)
		gComNextAt = (ai.teamId % 15) * SECOND;
	string why = "";
	if (gCsRule != gComDec)
		why = "rule";
	else if (ai.frame >= gComNextAt)
		why = gCsThreat ? "threat" : "clock";
	if (why != "") {
		ComDecide(u, why);
		gComNextAt = ai.frame + (gCsThreat ? 3 : 30) * SECOND;
	}
	u.SetDGunClose((gComDec == COM_FIGHT) || ((gComDec == COM_WORK) && !gCsThreat));
	ComEnforce(u);
	if (ai.frame >= gComStatAt) {
		gComStatAt = ai.frame + 60 * SECOND;
		string cn = "", rn = "", en = "";
		for (int o = 0; o < COM_N; ++o) {
			cn += ((o == 0) ? "" : "/") + gComChosenN[o];
			rn += ((o == 0) ? "" : "/") + gComRuleN[o];
			en += ((o == 0) ? "" : "/") + (gComEffF[o] / SECOND);
		}
		AiLog(Factory::T() + "apex: comstat t=" + ai.teamId + " dec=" + gComDecN
			+ " chosen(W/F/T/R)=" + cn + " rule=" + rn + " effSec=" + en
			+ " withdraw=" + gComWithdrawN + " drop=" + gComDropN + " explored=" + gComExpN
			+ " turret=" + gComTurN + " turretGunUp=" + gComTurHeld
			+ " dgunOrders=" + u.DGunOrders()
			+ " hp=" + int(gCsHp * 100.f) + " now=" + ComOptName(gComDec)
			+ " us avg=" + ((gComDecN > 0) ? int(gComUsSum / double(gComDecN)) : 0)
			+ " max=" + int(gComUsMax));
	}
}

// His job against the decision. A held job is never re-elected, so a
// withdrawal or a fight is ASSIGNED here (RemoveUnit on the idle task orphans
// him); a tower needs the election, so the builder job in its way is let go.
void ComEnforce(CCircuitUnit@ u)
{
	if (ai.frame - gComDropAt < 3 * SECOND)
		return;
	IUnitTask@ t = u.task;
	const int ty = (t is null) ? -1 : int(t.GetType());
	const int bt = (ty == int(Task::Type::BUILDER)) ? int(t.GetBuildType()) : -1;
	if ((gComDec == COM_RETREAT) || (gComDec == COM_FIGHT)) {
		// The engine's own retreat (he is hurt) heals him; overriding it each
		// time it re-arms on damage left him standing between the two.
		if (ty == int(Task::Type::RETREAT))
			return;
		// a fight lets work within his reach go on
		if ((gComDec == COM_FIGHT) && (bt >= 0) && (bt != int(Task::BuildType::PATROL))
			&& (t.GetBuildPos().distance2D(gCsHere) <= u.circuitDef.GetBuildDistance() + 100.f))
			return;
		IUnitTask@ pt = ComDecisionTask(u);
		if ((pt is null) || (pt is t))
			return;
		gComDropAt = ai.frame;
		++gComDropN;
		aiBuilderMgr.AssignTask(u, pt);
	} else if (gComDec == COM_TURRET) {
		if ((bt < 0) || (bt == int(Task::BuildType::DEFENCE)) || (ComSelfGun(u, false) is null))
			return;
		gComDropAt = ai.frame;
		++gComDropN;
		t.RemoveUnit(u);
	} else {
		return;
	}
	AiLog(Factory::T() + "apex: com-drop t=" + ai.teamId + " for=" + ComOptName(gComDec)
		+ " task=" + ty + "/" + bt
		+ " at=" + int(gCsHere.x) + "," + int(gCsHere.z) + " hp=" + int(gCsHp * 100.f));
}

// Away from them when the back of the base is no refuge: the step of 8 that
// puts the most ground between him and the nearest of them, the least
// enemy influence breaking ties.
AIFloat3 ComEvadePos(const AIFloat3& in here)
{
	AIFloat3 best = here;
	float bestScore = -1e9f;
	const float step = HERE_R;
	for (int k = 0; k < 8; ++k) {
		const float a = float(k) * 0.7853981634f;
		AIFloat3 p(here.x + cos(a) * step, here.y, here.z + sin(a) * step);
		if (!OnMap(p))
			continue;
		const float sc = p.distance2D(gCsFoeAt) - ai.GetEnemyInflAt(p);
		if (sc > bestScore) {
			bestScore = sc;
			best = p;
		}
	}
	return best;
}

// What CommanderSafety hands him under the decision; null = no override.
int gComRetLogAt = 0;
int gComEvadeN = 0;
int gComRetKeptN = 0;   // RETREAT kept the engine's own retreat task
IUnitTask@ ComDecisionTask(CCircuitUnit@ u)
{
	if (gComDec == COM_RETREAT) {
		const AIFloat3 here = u.GetPos(ai.frame);
		AIFloat3 to = gCsSafe;
		bool evade = false;
		if (!OnMap(to) || (here.distance2D(to) <= u.circuitDef.GetBuildDistance())) {
			// At the back of the base and still losing: step away from them
			// once they are in reach.
			if (!gCsThreat || !OnMap(gCsFoeAt) || (gCsArrive > gCsTowerS))
				return null;
			to = ComEvadePos(here);
			if (to.distance2D(here) < 1.f)
				return null;
			evade = true;
		}
		IUnitTask@ held = u.task;
		if ((held !is null) && (held.GetType() == Task::Type::BUILDER)
			&& (held.GetBuildType() == Task::BuildType::PATROL)
			&& (held.GetBuildPos().distance2D(to) < 300.f))
			return held;
		// Already on the engine's own retreat (hurt, going for repair): that is a
		// retreat too, and replacing it each election fights it.
		if ((held !is null) && (held.GetType() == Task::Type::RETREAT)) {
			++gComRetKeptN;
			return held;
		}
		const float spd = (Catalog::gSpeed[int(u.circuitDef.id)] > 1.f) ? Catalog::gSpeed[int(u.circuitDef.id)] : 1.f;
		const int dwell = int((here.distance2D(to) / spd + 10.f) * SECOND);
		IUnitTask@ pt = aiBuilderMgr.Enqueue(TaskB::Move(Task::Priority::HIGH, to, dwell));
		if (evade)
			++gComEvadeN;
		if ((pt !is null) && (ai.frame >= gComRetLogAt)) {
			gComRetLogAt = ai.frame + 10 * SECOND;
			float gd = 0.f, gh = 0.f;
			ComGunAt(to, gd, gh);
			AiLog(Factory::T() + "apex: com-retreat t=" + ai.teamId + (evade ? " evade" : "")
				+ " to=" + int(to.x) + "," + int(to.z)
				+ " d=" + int(here.distance2D(to)) + " gunDps=" + int(gd) + " evades=" + gComEvadeN + " keptRetreat=" + gComRetKeptN);
		}
		return pt;
	}
	if (gComDec == COM_FIGHT) {
		// Close only on what he can catch; a raider comes to him.
		if (gCsThreat && OnMap(gCsFoeAt) && (gCsFoeSpd <= Catalog::gSpeed[int(u.circuitDef.id)])
			&& !ComFar(gCsFoeAt))
		{
			IUnitTask@ held = u.task;
			if ((held !is null) && (held.GetType() == Task::Type::BUILDER)
				&& (held.GetBuildPos().distance2D(gCsFoeAt) < 300.f)
				&& (held.GetBuildType() == Task::BuildType::PATROL))
				return held;
			IUnitTask@ pt = aiBuilderMgr.Enqueue(TaskB::Patrol(Task::Priority::HIGH, gCsFoeAt, 15 * SECOND));
			if (pt !is null) {
				gCommEngageAt = ai.frame;
				return pt;
			}
		}
	}
	return null;
}

// A claim at `pos` asks what can catch him there before he is back under guns.
float ComClaimHpAfter(CCircuitUnit@ u, const AIFloat3& in pos, bool& out heavy)
{
	heavy = false;
	const int cd = int(u.circuitDef.id);
	const float spd = (Catalog::gSpeed[cd] > 1.f) ? Catalog::gSpeed[cd] : 1.f;
	ComTowersFill();
	float back = Builder::gHomeSet ? pos.distance2D(Builder::gHomePos) : 0.f;
	for (uint i = 0; i < gCdTwPos.length(); ++i) {
		const float d = pos.distance2D(gCdTwPos[i]) - gCdTwRng[i];
		if (d < back)
			back = (d > 0.f) ? d : 0.f;
	}
	const float tBack = back / spd;
	const float hp = u.GetHealthPercent();
	float fHp = 0.f, fDps = 0.f, vmax = 0.f;
	int n = 0;
	for (uint i = 0; i < gCrGp.length(); ++i) {
		const float dd = gCrGp[i].distance2D(pos);
		const float arr = (gCrSpd[i] > 0.f) ? ((dd > gCrRng[i]) ? (dd - gCrRng[i]) / gCrSpd[i] : 0.f)
				: ((dd <= gCrRng[i]) ? 0.f : 1e9f);
		if (arr > tBack)
			continue;
		if (gCrHeavy[i])
			heavy = true;
		fHp += gCrHp[i];
		fDps += gCrDps[i];
		n += gCrN[i];
		if (gCrSpd[i] > vmax)
			vmax = gCrSpd[i];
	}
	if (n <= 0)
		return hp;
	float gd = 0.f, gh = 0.f, s = 0.f;
	ComGunAt(pos, gd, gh);
	ComFightHpAfter(hp, Catalog::gHealth[cd], Catalog::gDps[cd], gd, gh, fDps, fHp, 0.f, n, s);
	const float kills = ComDGunKills(u, s, vmax, 12.f, n);
	return ComFightHpAfter(hp, Catalog::gHealth[cd], Catalog::gDps[cd], gd, gh, fDps, fHp, kills, n, s);
}

// Called where COMMANDER LOST is logged: what the assessment said last.
void ComDeathNote()
{
	AiLog(Factory::T() + "apex: com-death t=" + ai.teamId + " dec=" + ComOptName(gComDec)
		+ " decAgo=" + ((ai.frame - gComDecAt) / SECOND) + "s rule=" + ComOptName(gCsRule)
		+ " home=" + int(gCsHomeD) + " job=" + gCsJob + " withdraw=" + gComWithdrawN
		+ " " + ComSitText());
}

}  // namespace Market
