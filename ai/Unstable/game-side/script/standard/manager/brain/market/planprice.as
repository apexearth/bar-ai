namespace Market {

// TEAM STRATEGY, STEP 1 -- PRICE EVERY PLAN AND LOG IT, ACT ON NOTHING (his 10-24: "the team strategy should be
// based on what they think will work"; "timing is so important on a lot of these and the context/ability in the game
// is important"; TODO.md "Team strategies that shift"). Every 30 s each seat publishes what it holds; the lowest
// seat that has published prices, from what the team has SEEN, what each plan nets over the plan window
// (NG_HOLD_S): the square-law ground fight and the air sortie through their AA of Air::TairPlanEval, with their
// spending split into AA, fighters, turrets, army and economy (Air::TairFoeSplit) -- so their AA buys a ground plan
// its value. A rush is priced per land plant we can build, on its best fighter's power per metal and its walk to
// them, at the strike time that pays best. Logged as `apex: plan-price`; nothing reads it yet.

const int PP_AT = 8000, PP_INC = 8100, PP_ARMY = 8200, PP_AIR = 8300, PP_ECO = 8400;
int gPpNextAt = 0;
float gPpAA0 = -1.f;
int gPpAA0At = -1;
float gPpAAPrev = -1.f;

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

void PlanPriceTick()
{
	if (ai.frame < gPpNextAt)
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
	const AIFloat3 foe = Air::NaFoe();
	Air::NaSnapEnemy(OnMap(foe) ? foe : Builder::gHomePos);
	Air::TairFoeSplit();
	const float fAA = Air::gTairFoeAAM, fFtr = Air::gTairFoeFtrM, fDef = Air::gTairFoeDefM;
	const float fArmy = Air::gTairFoeArmyM, fEco = Air::gTairFoeEcoM;
	// their income, unseen: ours, scaled by the economy we have seen of theirs once there is some to see
	float If = I;
	if ((fEco > 0.2f * ourEco) && (ourEco > 1.f)) {
		float k = fEco / ourEco;
		k = (k < 0.5f) ? 0.5f : ((k > 2.f) ? 2.f : k);
		If = I * k;
	}
	const float a = Brain::TargetShare(Brain::ARMY);
	const float H = float(NG_HOLD_S);
	const float hz = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	const float gamma = H / ((hz > 1.f) ? hz : 300.f);   // a metal put into economy instead returns this much in H
	const float q = Military::TradeRatio();
	float G0 = Military::TeamArmyCost() - airM;
	if (G0 < 0.f)
		G0 = 0.f;
	const float E0 = fArmy + fDef;
	const float Eh = E0 + If * a * H;
	const AIFloat3 from = Builder::gHomePos;
	// NORMAL: the army share into the usual mix, the air we have on one sortie
	const float air0 = Air::TairAirNet(airM, from);
	const float vNorm = Air::TairGround(G0 + I * a * H, Eh, q, fEco, ourEco) + air0;
	// AIR: the army share into air, one massed sortie through their AA; the ground army stands as it is
	const float airS = I * a * H;
	const float vAir = Air::TairGround(G0, Eh, q, fEco, ourEco) + Air::TairAirNet(airM + airS, from);
	// GREED: half the army share into economy; what their army takes if it comes is the price
	const float gExtra = I * 0.5f * a * H;
	float gFight = Air::TairGround(G0 + I * 0.5f * a * H, Eh, q, fEco, ourEco);
	const float vGreed = gExtra * gamma + ((gFight < 0.f) ? gFight : 0.f) + air0;
	string line = "NORMAL=" + int(vNorm) + " AIR=" + int(vAir) + "(airS=" + int(airS) + ") GREED=" + int(vGreed);
	string best = "NORMAL";
	float bestV = vNorm;
	if (vAir > bestV) { bestV = vAir; best = "AIR"; }
	if (vGreed > bestV) { bestV = vGreed; best = "GREED"; }
	// RUSH per land plant: all income into its best fighter for T seconds, priced per second over the window
	array<int> plants;
	array<int> fighters;
	float powSum = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::ValidId(d) || !Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| (Catalog::gBuildsList[d].length() == 0) || (PlantClass(d) != PC_LAND) || (TreeTier(d) > 2))
			continue;
		int bf = -1;
		float bp = 0.f;
		const array<int>@ bo = Catalog::gBuildsList[d];
		for (uint i = 0; i < bo.length(); ++i) {
			const int u = bo[i];
			if (!Catalog::ValidId(u) || !Catalog::gMobile[u] || Catalog::gFlyer[u] || Catalog::gBuilder[u]
				|| Catalog::gKamikaze[u])   // a crawling bomb's blast read as dps: the Tumbleweed scored 9.5x
				continue;
			const float p = PpPower(u);
			if (p > bp) {
				bp = p;
				bf = u;
			}
		}
		if (bf < 0)
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
				const float E = E0 + If * a * (float(T) + arr);
				const float net = Air::TairGround(G, E, q, fEco, ourEco) - (1.f - a) * I * float(T) * gamma;
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
		if (reach && (v > bestV)) {
			bestV = v;
			best = "RUSH:" + Catalog::Def(plants[i]).GetName();
		}
	}
	// their answer: the AA they have added over the last two minutes (the follow-up a ground plan reads)
	if ((gPpAA0At < 0) || (ai.frame - gPpAA0At >= 120 * SECOND)) {
		gPpAAPrev = gPpAA0;
		gPpAA0 = fAA;
		gPpAA0At = ai.frame;
	}
	const float dAA = (gPpAAPrev >= 0.f) ? (fAA - gPpAAPrev) : 0.f;
	AiLog(Factory::T() + "apex: plan-price t=" + me + " seats=" + seats + " best=" + best + " cur=" + NgName(gPlan)
		+ " | " + line
		+ " | foe army=" + int(fArmy) + " def=" + int(fDef) + " aa=" + int(fAA) + " ftr=" + int(fFtr)
		+ " eco=" + int(fEco) + " inc~" + int(If) + " dAA2m=" + int(dAA)
		+ " | ours inc=" + int(I) + " gnd=" + int(G0) + " air=" + int(airM) + " eco=" + int(ourEco)
		+ " q=" + NnF(q, 2) + " share=" + NnF(a, 2));
	Perf::Add("plan.price", _t);
}

}  // namespace Market
