namespace Market {

// TEAM STRATEGY, STEP 1 -- PRICE EVERY PLAN AND LOG IT, ACT ON NOTHING (his 10-24: "the team strategy should be
// based on what they think will work"; "timing is so important on a lot of these and the context/ability in the game
// is important"; TODO.md "Team strategies that shift"). Every 30 s each seat publishes what it holds; the lowest
// seat that has published prices, from what the team has SEEN, what each plan nets over the plan window
// (NG_HOLD_S). A ground strike fights their army square-law, then takes the economy no turret covers, then fights
// the turrets for what they cover (his 10-24: turrets count only where they stand); the air sortie flies through
// their seen AA (Air::TairAirNet). A rush is priced per land plant on its best fighter's power per metal and its walk
// to them, at the strike time that pays best. Logged as `apex: plan-price`; nothing reads it yet.

const int PP_AT = 8000, PP_INC = 8100, PP_ARMY = 8200, PP_AIR = 8300, PP_ECO = 8400;
const int PP_THEIRS = 8520, PP_THEIRS_AT = 8521, PP_IRATIO = 8522;   // the leader's sighting, for every seat
const int PP_CHOICE = 8523;
const int PP_FOEARMY = 8524, PP_FOEDEF = 8525;   // their mobile army as the threat mod reads it; their turrets   // the plan the pricer chose (apex_plan_from_price)
int gPpNextAt = 0;
int gPpSayAt = 0;
// STEP 2: THE TEAM PLAYS WHAT IT PRICES BEST (apex_plan_from_price; his 10-24: "do our plans ever change? I'm only
// ever seeing rush"). The leader adopts the best-priced plan once it beats the one played by a fifth of its size
// (at least 1,000) on two readings running, a minute; every seat reads the choice from the board, so the switch is
// whole and at once. The pricer's names onto the team plans: RUSH:<lab> -> RUSH, LRT2 -> ARTY, NUKE -> MISSILE.
int gPpChoice = -1;
int gPpPending = -1;
int gPpPendN = 0;
bool PlanFromPriceOn()
{
	return ai.GetTunable("apex_plan_from_price", TUNE_PLAN_FROM_PRICE) > 0.f;
}
int PpNgOf(const string &in n)
{
	if (n.findFirst("RUSH") == 0) return NG_RUSH;
	if (n == "AIR") return NG_AIR;
	if (n == "GREED") return NG_GREED;
	if (n == "LRT2") return NG_ARTY;
	if (n == "T3") return NG_T3;
	if (n == "NUKE") return NG_MISSILE;
	return NG_NORMAL;
}
float PpValueOfNg(int ng)
{
	float v = -1e12f;
	for (uint i = 0; i < gPpSayN.length(); ++i) {
		if ((PpNgOf(gPpSayN[i]) == ng) && (gPpSayV[i] > v))
			v = gPpSayV[i];
	}
	return v;
}
void PpChoose(const string &in best, float bestV)
{
	if (!PlanFromPriceOn())
		return;
	const int ng = PpNgOf(best);
	if (gPpChoice < 0) {
		gPpChoice = ng;
		Say("plan -> " + NgName(ng) + " (priced best, " + int(bestV) + ")");
	} else if (ng != gPpChoice) {
		const float cur = PpValueOfNg(gPpChoice);
		const float margin = 0.2f * ((abs(cur) > 1000.f) ? abs(cur) : 1000.f);
		if (bestV > cur + margin) {
			gPpPendN = (gPpPending == ng) ? gPpPendN + 1 : 1;
			gPpPending = ng;
			if (gPpPendN >= 2) {
				Say("plan " + NgName(gPpChoice) + " -> " + NgName(ng) + " (" + best + " " + int(bestV) + " vs " + int(cur) + ")");
				AiLog(Factory::T() + "apex: plan-choice t=" + ai.teamId + " " + NgName(gPpChoice) + " -> " + NgName(ng)
					+ " best=" + best + " v=" + int(bestV) + " cur=" + int(cur));
				gPpChoice = ng;
				gPpPendN = 0;
			}
		} else {
			gPpPendN = 0;
		}
	} else {
		gPpPendN = 0;
	}
	ai.SetTeamBoard(PP_CHOICE, float(gPpChoice));
}
array<string> gPpSayN;
array<float> gPpSayV;
void PpSayAdd(const string &in n, float v)
{
	gPpSayN.insertLast(n);
	gPpSayV.insertLast(v);
}
float gPpAA0 = -1.f;
int gPpAA0At = -1;
float gPpAAPrev = -1.f;

// What we have seen of theirs, by place: turrets and the economy they cover.
float gPpIf = 0.f;   // their income as last estimated
float gPpArmyNow = 0.f;
float gPpArmy = 0.f, gPpDef = 0.f, gPpEcoFree = 0.f, gPpEcoCov = 0.f, gPpTurretR = 0.f;
array<float> gPpClusterM;   // their economy per 800-elmo cell, richest first
array<AIFloat3> gPpClusterP;

float PpOwnAirM()
{
	float m = 0.f;
	const array<int>@ own = OwnedDefs();
	for (uint i = 0; i < own.length(); ++i) {
		const int d = own[i];
		if (Catalog::ValidId(d) && Catalog::gFlyer[d] && Catalog::gMobile[d] && !Catalog::gBuilder[d]
			&& (Catalog::gDps[d] > 0.f) && (uint(d) < gOwnCount.length()))
			m += float(gOwnCount[d]) * Catalog::gCostM[d];
	}
	return m;
}

bool PpFresh(int t)
{
	return float(ai.frame) - ai.GetTeamBoard(PP_AT + t, -1e9f) < float(45 * SECOND);
}

// Square-law strength per metal against ground, for comparing one plant's best fighter with another's.
float PpPower(int d)
{
	if (!Catalog::ValidId(d) || (Catalog::gCostM[d] <= 0.f))
		return 0.f;
	const float dps = Catalog::gSurfDps[d];
	const float hp = Catalog::gHealth[d];
	return (dps > 0.f) && (hp > 0.f) ? sqrt(dps * hp) / Catalog::gCostM[d] : 0.f;
}

// what our tree reaches from what we own, walked through every builder and plant on the way
array<bool> gPpTree;
void PpTreeRefresh()
{
	gPpTree.resize(Catalog::gDefCount + 1);
	for (uint k = 0; k < gPpTree.length(); ++k)
		gPpTree[k] = false;
	array<int> open;
	const array<int>@ own = OwnedDefs();
	for (uint i = 0; i < own.length(); ++i) {
		const int d = own[i];
		if (Catalog::ValidId(d) && !gPpTree[d]) {
			gPpTree[d] = true;
			open.insertLast(d);
		}
	}
	while (open.length() > 0) {
		const int d = open[open.length() - 1];
		open.removeLast();
		const array<int>@ bo = Catalog::gBuildsList[d];
		for (uint i = 0; i < bo.length(); ++i) {
			const int b = bo[i];
			if (Catalog::ValidId(b) && Catalog::gAvailable[b] && !gPpTree[b]) {
				gPpTree[b] = true;
				open.insertLast(b);
			}
		}
	}
}
bool PpInTree(int d)
{
	return (d > 0) && (d < int(gPpTree.length())) && gPpTree[d];
}

void PpFoeScan()
{
	gPpArmy = 0.f; gPpDef = 0.f; gPpEcoFree = 0.f; gPpEcoCov = 0.f; gPpTurretR = 0.f;
	gPpArmyNow = 0.f;
	// a unit last seen longer ago than one walk to them counts at walk/age: it has fought, died or moved since
	const float fresh = StrikeEta() * SECOND;
	gPpClusterM.resize(0);
	gPpClusterP.resize(0);
	array<AIFloat3> tp;
	array<float> tr;
	array<AIFloat3> ep;
	array<float> em;
	const int total = aiEnemyMgr.GetEnemyUnitTotal();
	for (int i = 0; i < total; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d <= 0) || (d > Catalog::gDefCount))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			continue;
		const AIFloat3 p = aiEnemyMgr.GetEnemyUnitPosAt(i);
		const float m = Catalog::gCostM[d];
		const bool armed = (Catalog::gSurfDps[d] > 0.f) && (Catalog::gMaxRange[d] > 0.f);
		if (Catalog::gMobile[d]) {
			if (armed && !Catalog::gFlyer[d] && !Catalog::gBuilder[d]) {
				gPpArmy += m;
				const float age = float(ai.frame - aiEnemyMgr.GetEnemyUnitSeenAt(i));
				gPpArmyNow += (age <= fresh) ? m : m * fresh / age;
			}
			continue;
		}
		if (armed && (Catalog::gSurfT[d] > 0.f)) {
			gPpDef += m;
			const float r = (Catalog::gLandRange[d] > 0.f) ? Catalog::gLandRange[d] : Catalog::gMaxRange[d];
			tp.insertLast(p);
			tr.insertLast(r);
			if (r > gPpTurretR)
				gPpTurretR = r;
		} else if (!armed && OnMap(p)) {
			ep.insertLast(p);
			em.insertLast(m);
		}
	}
	array<int> key;
	for (uint e = 0; e < ep.length(); ++e) {
		bool cov = false;
		for (uint t = 0; (t < tp.length()) && !cov; ++t)
			cov = ep[e].distance2D(tp[t]) < tr[t];
		if (cov)
			gPpEcoCov += em[e];
		else
			gPpEcoFree += em[e];
		const int k = int(ep[e].x / 800.f) * 1000 + int(ep[e].z / 800.f);
		int j = key.find(k);
		if (j < 0) {
			key.insertLast(k);
			gPpClusterM.insertLast(0.f);
			gPpClusterP.insertLast(ep[e]);
			j = int(key.length()) - 1;
		}
		gPpClusterM[uint(j)] += em[e];
	}
	// richest first (a handful of cells: selection order is fine)
	for (uint i = 0; i < gPpClusterM.length(); ++i) {
		uint b = i;
		for (uint j = i + 1; j < gPpClusterM.length(); ++j) {
			if (gPpClusterM[j] > gPpClusterM[b])
				b = j;
		}
		if (b != i) {
			const float tm = gPpClusterM[i]; gPpClusterM[i] = gPpClusterM[b]; gPpClusterM[b] = tm;
			const AIFloat3 tq = gPpClusterP[i]; gPpClusterP[i] = gPpClusterP[b]; gPpClusterP[b] = tq;
		}
	}
}

// A strike of G (metal, already scaled by its power) against their army, then the economy no turret covers, then
// their turrets for what they cover; lr: our strike outranges their turrets and kills them without loss. Net metal:
// what we destroy less what we lose; a lost fight lets their survivors into our economy.
float PpStrike(float G, float A, float D, float free, float cov, float q, float ourEco, bool lr)
{
	if (G <= 0.f)
		return 0.f;
	if (q <= 0.f)
		q = 1.f;
	float lost = 0.f, killed = 0.f, gs = G;
	if (A > 0.f) {
		if (q * G * G < A * A) {
			const float es = sqrt(A * A - q * G * G);
			return (A - es) - (G + ((es < ourEco) ? es : ourEco));
		}
		gs = sqrt(G * G - A * A / q);
		lost += G - gs;
		killed += A;
	}
	killed += (gs < free) ? gs : free;
	if ((cov <= 0.f) && (D <= 0.f))
		return killed - lost;
	if (lr) {
		killed += D + ((gs < cov) ? gs : cov);
		return killed - lost;
	}
	if (q * gs * gs >= D * D) {
		const float g3 = sqrt(gs * gs - D * D / q);
		lost += gs - g3;
		killed += D + ((g3 < cov) ? g3 : cov);
	} else {
		killed += D - sqrt(D * D - q * gs * gs);
		lost += gs;
	}
	return killed - lost;
}

// The cheapest available plant of a super class (gantry, silo): its bill, -1 if none.
float PpSuperBill(int sc, int &out def)
{
	def = -1;
	float best = -1.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::ValidId(d) || !PpInTree(d) || Catalog::gMobile[d] || (SuperClassOf(d) != sc))
			continue;
		const float b = SuperBill(d);
		if ((best < 0.f) || (b < best)) {
			best = b;
			def = d;
		}
	}
	return best;
}

void PlanPriceTick()
{
	// the bisect switch: is the log-only pricer moving the live air state? (his 10-24: "we seem to do worse *every
	// game*" -- the control without the play lost to v0.4.02 too)
	if ((ai.frame < gPpNextAt) || (ai.GetTunable("apex_plan_price", TUNE_PLAN_PRICE) <= 0.f))
		return;
	gPpNextAt = ai.frame + 30 * SECOND;
	const int me = ai.teamId;
	ai.SetTeamBoard(PP_AT + me, float(ai.frame));
	ai.SetTeamBoard(PP_INC + me, Eco::MInc());
	ai.SetTeamBoard(PP_ARMY + me, ArmyValue());
	const float myAir = PpOwnAirM();
	ai.SetTeamBoard(PP_AIR + me, myAir);
	ai.SetTeamBoard(PP_ECO + me, gAssetsM);
	int lead = me;
	for (int t = 0; t < 64; ++t) {
		if (PpFresh(t)) {
			lead = t;
			break;
		}
	}
	if ((lead != me) || !Builder::gHomeSet || (ai.frame < 3 * 60 * SECOND))
		return;
	const double _t = Perf::T0();
	float I = 0.f, airM = 0.f, ourEco = 0.f;
	int seats = 0;
	for (int t = 0; t < 64; ++t) {
		if (!PpFresh(t))
			continue;
		++seats;
		I += ai.GetTeamBoard(PP_INC + t, 0.f);
		airM += ai.GetTeamBoard(PP_AIR + t, 0.f);
		ourEco += ai.GetTeamBoard(PP_ECO + t, 0.f);
	}
	// THE PRICER MUST NOT TOUCH THE LIVE AIR STATE: its sortie resets the run floors (gNaObsDmg/gNaObsLost) and its
	// snapshot and candidate list are the per-frame caches the real air decision reads. Measured: pricer off vs on,
	// same 8 seeds vs v0.4.02 at +50 -- trade 1.13 vs 0.76, better in 6 of 8. Saved here, restored and invalidated
	// below.
	const float savedObsDmg = Air::gNaObsDmg;
	const float savedObsLost = Air::gNaObsLost;
	const AIFloat3 foe = Air::NaFoe();
	Air::NaSnapEnemy(OnMap(foe) ? foe : Builder::gHomePos);
	Air::TairFoeSplit();
	PpTreeRefresh();
	PpFoeScan();
	const float fAA = Air::gTairFoeAAM, fFtr = Air::gTairFoeFtrM;
	const float A0 = gPpArmy, D = gPpDef, free = gPpEcoFree, cov = gPpEcoCov;
	const float fEco = free + cov;
	float If = I;
	if ((fEco > 0.2f * ourEco) && (ourEco > 1.f)) {
		float k = fEco / ourEco;
		k = (k < 0.5f) ? 0.5f : ((k > 2.f) ? 2.f : k);
		If = I * k;
	}
	gPpIf = If;
	{
		const float covShare = (fEco > 1.f) ? cov / fEco : 1.f;
		ai.SetTeamBoard(PP_THEIRS, A0 + D * covShare);
		ai.SetTeamBoard(PP_THEIRS_AT, float(ai.frame));
		ai.SetTeamBoard(PP_FOEARMY, gPpArmyNow);
		ai.SetTeamBoard(PP_FOEDEF, D);
		ai.SetTeamBoard(PP_IRATIO, (I > 1.f) ? If / I : 1.f);
	}
	const float a = Brain::TargetShare(Brain::ARMY);
	const float H = float(NG_HOLD_S);
	const float hz = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	const float gamma = H / ((hz > 1.f) ? hz : 300.f);   // a metal put into economy instead returns this much in H
	const float q = Military::TradeRatio();
	float G0 = Military::TeamArmyCost() - airM;
	if (G0 < 0.f)
		G0 = 0.f;
	const float Ah = A0 + If * a * H;
	const AIFloat3 from = Builder::gHomePos;
	const float air0 = Air::TairAirNet(airM, from);
	const float vNorm = PpStrike(G0 + I * a * H, Ah, D, free, cov, q, ourEco, false) + air0;
	const float airS = I * a * H;
	const float vAir = PpStrike(G0, Ah, D, free, cov, q, ourEco, false) + Air::TairAirNet(airM + airS, from);
	const float gFight = PpStrike(G0 + I * 0.5f * a * H, Ah, D, free, cov, q, ourEco, false);
	const float vGreed = I * 0.5f * a * H * gamma + ((gFight < 0.f) ? gFight : 0.f) + air0;
	string line = "NORMAL=" + int(vNorm) + " AIR=" + int(vAir) + "(airS=" + int(airS) + ") GREED=" + int(vGreed);
	gPpSayN.resize(0);
	gPpSayV.resize(0);
	PpSayAdd("NORMAL", vNorm);
	PpSayAdd("AIR", vAir);
	PpSayAdd("GREED", vGreed);
	string best = "NORMAL";
	float bestV = vNorm;
	if (vAir > bestV) { bestV = vAir; best = "AIR"; }
	if (vGreed > bestV) { bestV = vGreed; best = "GREED"; }
	// land plants: each one's best fighter, and the best that outranges every turret we have seen
	array<int> plants;
	array<int> fighters;
	float powSum = 0.f;
	int lrDef = -1, t3Def = -1;
	float lrPow = 0.f, t3Pow = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::ValidId(d) || !PpInTree(d) || Catalog::gMobile[d]
			|| (Catalog::gBuildsList[d].length() == 0) || (PlantClass(d) != PC_LAND))
			continue;
		const int tier = TreeTier(d);
		int bf = -1;
		float bp = 0.f;
		const array<int>@ bo = Catalog::gBuildsList[d];
		for (uint i = 0; i < bo.length(); ++i) {
			const int u = bo[i];
			if (!Catalog::ValidId(u) || !Catalog::gMobile[u] || Catalog::gFlyer[u] || Catalog::gBuilder[u]
				|| Catalog::gKamikaze[u])   // a crawling bomb's blast read as dps: the Tumbleweed scored 9.5x
				continue;
			const float p = PpPower(u);
			if (tier >= 3) {
				if (p > t3Pow) { t3Pow = p; t3Def = u; }
				continue;
			}
			if ((tier == 2) && (Catalog::gLandRange[u] > gPpTurretR) && (gPpTurretR > 0.f) && (p > lrPow)) {
				lrPow = p;
				lrDef = u;
			}
			if (p > bp) {
				bp = p;
				bf = u;
			}
		}
		if ((tier >= 3) || (bf < 0))
			continue;
		bool dup = false;
		for (uint i = 0; i < fighters.length() && !dup; ++i)
			dup = (fighters[i] == bf);
		if (dup)
			continue;
		plants.insertLast(d);
		fighters.insertLast(bf);
		powSum += bp;
	}
	const AIFloat3 foeBox = ai.GetNearestEnemyBox(from);
	const float powRef = (plants.length() > 0) ? powSum / float(plants.length()) : 1.f;
	for (uint i = 0; i < plants.length(); ++i) {
		const int u = fighters[i];
		const float k = (powRef > 0.f) ? PpPower(u) / powRef : 1.f;
		const bool reach = OnMap(foeBox) && ai.CanDefReachAt(Catalog::Def(u), from, foeBox, 300.f);
		const float spd = (Catalog::gSpeed[u] > 1.f) ? Catalog::gSpeed[u] : 30.f;
		const float arr = OnMap(foeBox) ? from.distance2D(foeBox) / spd : 120.f;
		float bestRate = -1e9f;
		int bestT = 0;
		if (reach) {
			for (int T = 60; T <= int(H); T += 60) {
				const float G = (G0 + I * float(T)) * k;
				const float Ar = A0 + If * a * (float(T) + arr);
				const float net = PpStrike(G, Ar, D, free, cov, q, ourEco, false) - (1.f - a) * I * float(T) * gamma;
				const float rate = net / (float(T) + arr);
				if (rate > bestRate) {
					bestRate = rate;
					bestT = T;
				}
			}
		}
		const float v = reach ? bestRate * H : 0.f;
		line += " RUSH:" + Catalog::Def(plants[i]).GetName() + "/" + Catalog::Def(u).GetName() + "="
			+ (reach ? ("" + int(v) + "(T=" + bestT + " k=" + NnF(k, 2) + " walk=" + int(arr) + ")") : "unreachable");
		if (reach)
			PpSayAdd("RUSH:" + Catalog::Def(plants[i]).GetName(), v);
		if (reach && (v > bestV)) {
			bestV = v;
			best = "RUSH:" + Catalog::Def(plants[i]).GetName();
		}
	}
	// LONG-RANGE T2: the army share into the best T2 fighter that outranges every turret seen; it shells the turrets
	// without loss once their army is beaten
	if (lrDef > 0) {
		const float k = (powRef > 0.f) ? lrPow / powRef : 1.f;
		const float v = PpStrike((G0 + I * a * H) * k, Ah, D, free, cov, q, ourEco, true) + air0;
		line += " LRT2/" + Catalog::Def(lrDef).GetName() + "=" + int(v) + "(range " + int(Catalog::gLandRange[lrDef])
			+ ">" + int(gPpTurretR) + " k=" + NnF(k, 2) + ")";
		PpSayAdd("LRT2", v);
		if (v > bestV) { bestV = v; best = "LRT2"; }
	} else {
		line += " LRT2=none";
	}
	// T3: a gantry first, then the rest of the army share into its best unit
	{
		int gd = -1;
		const float gBill = PpSuperBill(SC_GANTRY, gd);
		const bool have = SuperHave(SC_GANTRY) > 0;
		if ((t3Def > 0) && ((gBill > 0.f) || have)) {
			const float k = (powRef > 0.f) ? t3Pow / powRef : 1.f;
			float spend = I * a * H - (have ? 0.f : gBill);
			if (spend < 0.f)
				spend = 0.f;
			const float v = PpStrike(G0 + spend * k, Ah, D, free, cov, q, ourEco, false) + air0;
			line += " T3/" + Catalog::Def(t3Def).GetName() + "=" + int(v) + "(gantry " + (have ? "stands" : ("" + int(gBill)))
				+ " k=" + NnF(k, 2) + ")";
			PpSayAdd("T3", v);
			if (v > bestV) { bestV = v; best = "T3"; }
		} else {
			line += " T3=none";
		}
	}
	// NUKE: a silo, then missiles from the army share; each lands on their richest economy cells, the antis covering
	// a cell stopping apex_nuke_per_anti each (Brain::AntisCovering)
	{
		int sd = -1;
		const float sBill = PpSuperBill(SC_SILO, sd);
		const float mBill = NUKE_MISSILE_M + NUKE_MISSILE_E * EPriceFloor();
		const bool have = SuperHave(SC_SILO) > 0;
		if (((sBill > 0.f) || have) && (mBill > 0.f)) {
			float budget = I * a * H - (have ? 0.f : sBill);
			int n = (budget > 0.f) ? int(budget / mBill) : 0;
			const int byClock = int(H / NUKE_STOCK_S) + 1;
			if (n > byClock)
				n = byClock;
			const float perAnti = ai.GetTunable("apex_nuke_per_anti", TUNE_NUKE_PER_ANTI);
			float prize = 0.f;
			int left = n;
			for (uint c = 0; (c < gPpClusterM.length()) && (left > 0); ++c) {
				const int need = 1 + int(float(Brain::AntisCovering(gPpClusterP[c])) * perAnti);
				if (need > left)
					continue;
				left -= need;
				prize += gPpClusterM[c];
			}
			const float v = prize - float(n) * mBill - (have ? 0.f : sBill) + PpStrike(G0, Ah, D, free, cov, q, ourEco, false);
			line += " NUKE=" + int(v) + "(missiles " + n + " prize " + int(prize) + ")";
			PpSayAdd("NUKE", v);
			if (v > bestV) { bestV = v; best = "NUKE"; }
		} else {
			line += " NUKE=none";
		}
	}
	PpChoose(best, bestV);
	if ((gPpAA0At < 0) || (ai.frame - gPpAA0At >= 120 * SECOND)) {
		gPpAAPrev = gPpAA0;
		gPpAA0 = fAA;
		gPpAA0At = ai.frame;
	}
	const float dAA = (gPpAAPrev >= 0.f) ? (fAA - gPpAAPrev) : 0.f;
	AiLog(Factory::T() + "apex: plan-price t=" + me + " seats=" + seats + " best=" + best + " cur=" + NgName(gPlan)
		+ " | " + line
		+ " | foe army=" + int(A0) + " def=" + int(D) + " turretR=" + int(gPpTurretR) + " aa=" + int(fAA)
		+ " ftr=" + int(fFtr) + " eco=" + int(fEco) + "(free " + int(free) + ") inc~" + int(If) + " dAA2m=" + int(dAA)
		+ " | ours inc=" + int(I) + " gnd=" + int(G0) + " air=" + int(airM) + " eco=" + int(ourEco)
		+ " q=" + NnF(q, 2) + " share=" + NnF(a, 2));
	if (SayOn()) {
		string s = "plans:";
		array<bool> used(gPpSayN.length(), false);
		for (int k = 0; k < 4; ++k) {
			int b = -1;
			for (uint i = 0; i < gPpSayN.length(); ++i) {
				if (!used[i] && ((b < 0) || (gPpSayV[i] > gPpSayV[uint(b)])))
					b = int(i);
			}
			if (b < 0)
				break;
			used[uint(b)] = true;
			s += " " + gPpSayN[uint(b)] + " " + int(gPpSayV[uint(b)]);
		}
		gThinkPlans = s + " | theirs army " + int(A0) + " turrets " + int(D) + " AA " + int(fAA) + " | ours " + int(G0);
	}
	Air::gNaObsDmg = savedObsDmg;
	Air::gNaObsLost = savedObsLost;
	Air::gNaSnapAt = -1;
	Air::gNaCsAt = -1;
	Perf::Add("plan.price", _t);
}

}  // namespace Market
