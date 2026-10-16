namespace Market {

// EARLY BALL (apex_early_ball, his 2026-10-16: "if we had a ball of ~10-20 pawns we could
// probably take out an enemy base"). Rides smallhard's contact k, Tc walk and their army rate,
// so a large map (k = 0) prices exactly as before. Refreshed every 5 s; elections read the cache.
// Their base when the ball arrives (one seat): seen guns on their side / seats, their seen army
// / seats + Rs x (walk + build), their commander (our own def as the prior). A ball of N of def d
// against it, square law: N0^2 = Dd x Dh / (dps x hp) ties it; the survivors s = sqrt(1 - N0^2/N^2)
// raze structures until their new production m = Rs x t matches them, killing
//   K = (N^2 - N0^2) x a,   a = dps x sqrt(dps x hp / (qD x qH)) x metal-per-hp / Rs
// The ball that razes the whole stake: N^2 = N0^2 + stake / a, with the build time N x cost / our
// army rate inside N0 (solved, a quadratic in N). Worth per metal of it:
//   W = (stake + their guns and army it beat) / (N x cost) - (1 - s);  ppc x (1 + k x W)
// No finite ball (their production per our build beats the unit) or W <= 0: no term.

bool gEbOn = false;
bool gEbOnRead = false;
int gEbAt = -999999;
int gEbStamp = 0;
int gEbLogAt = 1800;
float gEbQD = 0.f, gEbQH = 0.f;
float gEbTowDps = 0.f, gEbTowHp = 0.f, gEbTowM = 0.f;
float gEbArmyAt = 0.f, gEbRs = 0.f, gEbStake = 0.f, gEbMph = 0.f;
float gEbComDps = 0.f, gEbComHp = 0.f;
float gEbWalk = 0.f, gEbRate = 0.f;
array<int> gEbDefAt;
array<float> gEbDefW;
array<float> gEbDefN;
array<float> gEbDefS;
int gEbBestDef = 0, gEbBestStamp = -1;
float gEbBestW = 0.f, gEbBestN = 0.f;
float gEbBar = 0.f;
float gEbFieldA = 0.f;
float gEbOurFieldA = 0.f;
float gEbScoutLos = 0.f;
int gEbSpotsAll = 0, gEbSpotsUnseen = 0;
float gEbGathered = 0.f, gEbGatheredM = 0.f;
array<IUnitTask@> gEbAtkSeen;
int gEbSentN = 0;
float gEbSentPow = 0.f, gEbSentM = 0.f;
float gEbKillM = 0.f, gEbLossM = 0.f;
int gEbKillN = 0, gEbLossN = 0;
array<int> gEbOrdDef;
array<int> gEbOrdN;
array<float> gEbLastPc;
array<float> gEbLastP;
array<float> gEbLastMul;
array<float> gEbLastCov;
array<int> gEbLastAt;
float gEbScoutV = 0.f, gEbScoutM1 = 0.f;
int gEbScoutBuys = 0;
array<int> gEbPpcFac;
array<int> gEbPpcNext;

float EbExp(float x) { return pow(2.7182818f, x); }   // the script math has no exp

bool EarlyBallOn()
{
	if (!gEbOnRead) {
		gEbOnRead = true;
		gEbOn = ai.GetTunable("apex_early_ball", TUNE_EARLY_BALL) > 0.f;
	}
	return gEbOn;
}

// Their basic line's dps and hp per metal: every ground fighter of every basic land plant.
void EbPriorsFill()
{
	if ((gEbQD > 0.f) && (gEbQH > 0.f))
		return;
	float sD = 0.f, sH = 0.f, sM = 0.f;
	for (int p = 1; p <= Catalog::gDefCount; ++p) {
		if (!Catalog::gAvailable[p] || Catalog::gMobile[p] || (PlantTier(p) != 1)
			|| (PlantClass(p) != PC_LAND))
			continue;
		const array<int>@ pr = Catalog::gBuildsList[p];
		for (uint q = 0; q < pr.length(); ++q) {
			const int d = pr[q];
			if (!Catalog::gAvailable[d] || !LineCombat(d) || Catalog::gFlyer[d]
				|| (Catalog::gSurfT[d] <= 0.01f) || (Catalog::gCostM[d] <= 0.f))
				continue;
			sD += Catalog::gDps[d];
			sH += Catalog::gHealth[d];
			sM += Catalog::gCostM[d];
		}
	}
	if (sM > 0.f) {
		gEbQD = sD / sM;
		gEbQH = sH / sM;
	}
	if (gEbScoutLos <= 0.f) {
		for (int d = 1; d <= Catalog::gDefCount; ++d) {
			if (Air::IsLookDef(d) && (Catalog::gLosR[d] > gEbScoutLos))
				gEbScoutLos = Catalog::gLosR[d];
		}
	}
}

// The field: the map's area, ours by seat share, and their unseen part by their spots we see nothing at.
void EbField()
{
	const float mapA = float(AiTerrainWidth()) * float(AiTerrainHeight());
	array<Id>@ mates = ai.GetTeamIds();
	const int ours = ((mates is null) || (mates.length() < 1)) ? 1 : int(mates.length());
	int foes = int(ai.GetEnemyTeamSize());
	if (foes < 1)
		foes = ours;
	gEbOurFieldA = mapA * float(ours) / float(ours + foes);
	gEbSpotsAll = int(gAllSpots.length());
	gEbSpotsUnseen = 0;
	const float r = (gEbScoutLos > 1.f) ? gEbScoutLos : 0.f;
	for (uint s = 0; (r > 0.f) && (s < gAllSpots.length()); ++s) {
		const AIFloat3 sp = gAllSpots[s];
		if ((Military::ForwardFraction(sp) > 0.5f) && (aiEnemyMgr.GetEnemyStructCostAt(sp, r) <= 1.f))
			++gEbSpotsUnseen;
	}
	gEbFieldA = (gEbSpotsAll > 0) ? mapA * float(gEbSpotsUnseen) / float(gEbSpotsAll) : 0.f;
}

void EbRefresh()
{
	gEbAt = ai.frame;
	++gEbStamp;
	EbPriorsFill();
	EbField();
	EbPoolScan();
	if (SmallHardK() <= 0.f)
		return;
	const int foes = (gSmhFoes > 0) ? gSmhFoes : 1;
	gEbRs = gSmhR / float(foes);
	gEbArmyAt = Military::EnemyArmyCost() / float(foes);
	gEbTowDps = 0.f;
	gEbTowHp = 0.f;
	gEbTowM = 0.f;
	const AIFloat3 home = Builder::gHomePos;
	const int nG = aiEnemyMgr.GetEnemyGroupCount();
	for (int gi = 0; gi < nG; ++gi) {
		const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(gi);
		if (!OnMap(gp) || (gp.distance2D(gSmhBox) >= gp.distance2D(home)))
			continue;
		const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(gi);
		for (int k = 0; k < nU; ++k) {
			const int d = aiEnemyMgr.GetEnemyGroupUnitDef(gi, k);
			if (!Catalog::ValidId(d) || Catalog::gMobile[d] || Catalog::gFlyer[d]
				|| (Catalog::gDps[d] <= 0.f) || (Catalog::gSurfT[d] <= 0.01f))
				continue;
			gEbTowDps += Catalog::gDps[d];
			gEbTowHp += Catalog::gHealth[d];
			gEbTowM += Catalog::gCostM[d];
		}
	}
	gEbTowDps /= float(foes);
	gEbTowHp /= float(foes);
	gEbTowM /= float(foes);
	gEbComDps = (gSmhComDef > 0) ? Catalog::gDps[gSmhComDef] : 0.f;
	gEbComHp = (gSmhComDef > 0) ? Catalog::gHealth[gSmhComDef] : 0.f;
	const float seenS = aiEnemyMgr.GetEnemyStructCost() / float(foes);
	const float mirror = EconAssetsM();
	gEbStake = (seenS > mirror) ? seenS : mirror;
	gEbMph = StructMetalPerHp();
	gEbWalk = (gSmhWalk > 0.f) ? gSmhWalk : gSmhLine * gSmhRho;
	gEbRate = Eco::MInc() * Brain::TargetShare(Brain::ARMY);
}

void EbBall(int d)
{
	if (int(gEbDefAt.length()) <= Catalog::gDefCount) {
		gEbDefAt.resize(Catalog::gDefCount + 1);
		gEbDefW.resize(Catalog::gDefCount + 1);
		gEbDefN.resize(Catalog::gDefCount + 1);
		gEbDefS.resize(Catalog::gDefCount + 1);
	}
	if (gEbDefAt[d] == gEbStamp)
		return;
	gEbDefAt[d] = gEbStamp;
	gEbDefW[d] = 0.f;
	gEbDefN[d] = 0.f;
	gEbDefS[d] = 0.f;
	const float dps = Catalog::gDps[d];
	const float hp = Catalog::gHealth[d];
	const float c = Catalog::gCostM[d];
	const float v = Catalog::gSpeed[d];
	if ((dps <= 0.f) || (hp <= 0.f) || (c <= 0.f) || (v <= 1.f) || Catalog::gFlyer[d]
		|| (Catalog::gSurfT[d] <= 0.01f) || (gEbWalk <= 0.f) || (gEbQD <= 0.f) || (gEbQH <= 0.f)
		|| (gEbRate <= 0.01f) || (gEbStake <= 0.f))
		return;
	const float fq = dps * hp;
	const float qq = gEbQD * gEbQH;
	const float rS = (gEbRs > 0.01f) ? gEbRs : 0.01f;
	const float a = dps * sqrt(fq / qq) * gEbMph / rS;
	const float m1 = gEbArmyAt + rS * gEbWalk / v;
	const float g = rS * c / gEbRate;
	const float P = gEbTowDps + gEbComDps + gEbQD * m1;
	const float Q = gEbTowHp + gEbComHp + gEbQH * m1;
	const float A2 = fq - qq * g * g;
	if (A2 <= 0.f)
		return;
	const float B2 = g * (P * gEbQH + Q * gEbQD);
	const float C2 = P * Q + fq * gEbStake / a;
	const float N = (B2 + sqrt(B2 * B2 + 4.f * A2 * C2)) / (2.f * A2);
	if (N <= 0.f)
		return;
	const float mA = m1 + g * N;
	const float n0sq = (P + gEbQD * g * N) * (Q + gEbQH * g * N) / fq;
	float s2 = 1.f - n0sq / (N * N);
	s2 = (s2 > 0.f) ? s2 : 0.f;
	const float s = sqrt(s2);
	const float W = (gEbStake + gEbTowM + mA) / (N * c) - (1.f - s);
	gEbDefN[d] = N;
	gEbDefS[d] = s;
	gEbDefW[d] = (W > 0.f) ? W : 0.f;
}

float EarlyBallMul(int d)
{
	if (!EarlyBallOn())
		return 1.f;
	const float k = SmallHardK();
	if (k <= 0.f)
		return 1.f;
	EbBall(d);
	const float W = gEbDefW[d];
	if ((W > 0.f) && ((gEbBestStamp != gEbStamp) || (W > gEbBestW))) {
		gEbBestStamp = gEbStamp;
		gEbBestDef = d;
		gEbBestW = W;
		gEbBestN = gEbDefN[d];
	}
	return 1.f + k * W;
}

// Ground watched per metal: N of them from the spend over the fill window, each seeing its own
// sight and sweeping it at its speed for the time their fastest raider takes to cross our field.
// The share watched, 1 - e^-x, saturates for every unit as income grows, so the ranking fades.
float EarlyBallCoverMul(int d, float incA, float fillS)
{
	if (!EarlyBallOn() || !CoverCapable(d) || PatrolFodder(d) || (gEbOurFieldA <= 0.f)
		|| (incA <= 0.f) || (Catalog::gCostM[d] <= 0.f))
		return 1.f;
	const float cap = FoeSpeedCap();
	if (cap <= 1.f)
		return 1.f;
	const float los = Catalog::gLosR[d];
	const float tx = sqrt(gEbOurFieldA) / cap;
	const float area = 3.14159f * los * los + 2.f * los * Catalog::gSpeed[d] * tx;
	const float x = incA * ((fillS > 1.f) ? fillS : 60.f) * area / (Catalog::gCostM[d] * gEbOurFieldA);
	return 2.f - EbExp(-x);
}

// An air scout: the enemy metal we cannot see, times the share of their unseen ground the next
// plane adds over the fill window -- k planes up sweep 1 - e^(-k x sweep / unseen area).
float EarlyBallScoutGain(int d, float fillS)
{
	if (!Air::IsLookDef(d) || Air::ScoutsDie() || (gEbFieldA <= 0.f))
		return 0.f;
	const float h = (fillS > 1.f) ? fillS : 180.f;
	float foeEst = Military::FoeBelievedM();
	foeEst = (ArmyValue() > foeEst) ? ArmyValue() : foeEst;
	float unseen = foeEst - Military::FoeLiveM();
	unseen = (unseen > 0.f) ? unseen : 0.f;
	const float eco = Air::MirrorPrize() - aiEnemyMgr.GetEnemyStructCost();
	unseen += (eco > 0.f) ? eco : 0.f;
	if (unseen <= 0.f)
		return 0.f;
	const float sweep = 2.f * Catalog::gLosR[d] * Catalog::gSpeed[d] * h;
	const float have = float(((int(d) < int(gOwnCount.length())) ? gOwnCount[d] : 0) + Brain::PendAnyOf(d));
	const float r = sweep / gEbFieldA;
	const float m = EbExp(-have * r) * (1.f - EbExp(-r));
	gEbScoutV = unseen;
	gEbScoutM1 = m;
	return unseen * m / h;
}

// The bar a massing pool promotes at: the ball the best-priced def wins with, in pool power.
float EarlyBallBar(float want)
{
	gEbBar = 0.f;
	if (!EarlyBallOn() || (SmallHardK() <= 0.f) || (gEbBestDef <= 0) || (gEbBestW <= 0.f)
		|| (gEbBestStamp < gEbStamp - 2))
		return want;
	gEbBar = gEbBestN * Catalog::gPower[gEbBestDef];
	return (gEbBar > want) ? gEbBar : want;
}

// What stands gathered at home and what left as an attack, by the pools' own tasks.
void EbPoolScan()
{
	gEbGathered = 0.f;
	gEbGatheredM = 0.f;
	array<IUnitTask@> tk;
	array<float> tp;
	array<float> tm;
	for (uint i = 0; i < Military::gCombatId.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(Military::gCombatId[i]));
		if ((u is null) || (u.circuitDef is null) || u.circuitDef.IsAbleToFly())
			continue;
		IUnitTask@ t = u.task;
		if ((t is null) || (t.GetType() != Task::Type::FIGHTER))
			continue;
		const int ud = int(u.circuitDef.id);
		int j = -1;
		for (uint q = 0; q < tk.length(); ++q) {
			if (tk[q] is t) {
				j = int(q);
				break;
			}
		}
		if (j < 0) {
			tk.insertLast(t);
			tp.insertLast(0.f);
			tm.insertLast(0.f);
			j = int(tk.length()) - 1;
		}
		tp[j] += Catalog::gPower[ud];
		tm[j] += Catalog::gCostM[ud];
	}
	array<IUnitTask@> atk;
	for (uint q = 0; q < tk.length(); ++q) {
		const int ft = tk[q].GetFightType();
		if ((ft == int(Task::FightType::DEFEND)) && (tp[q] > gEbGathered)) {
			gEbGathered = tp[q];
			gEbGatheredM = tm[q];
		}
		if (ft != int(Task::FightType::ATTACK))
			continue;
		atk.insertLast(tk[q]);
		bool seen = false;
		for (uint s = 0; s < gEbAtkSeen.length(); ++s) {
			if (gEbAtkSeen[s] is tk[q]) {
				seen = true;
				break;
			}
		}
		if (!seen) {
			++gEbSentN;
			gEbSentPow += tp[q];
			gEbSentM += tm[q];
		}
	}
	gEbAtkSeen = atk;
}

void EarlyBallNoteKill(int d, const AIFloat3& in pos, bool byUs)
{
	if (!byUs || !EarlyBallOn() || !Catalog::ValidId(d) || (Military::ForwardFraction(pos) <= 0.5f))
		return;
	gEbKillM += Catalog::gCostM[d];
	++gEbKillN;
}

void EarlyBallNoteLoss(CCircuitUnit@ u)
{
	if (!EarlyBallOn() || (u is null) || (u.circuitDef is null))
		return;
	const int d = int(u.circuitDef.id);
	if (!LineCombat(d) || Catalog::gFlyer[d] || (Military::ForwardFraction(u.GetPos(ai.frame)) <= 0.5f))
		return;
	gEbLossM += Catalog::gCostM[d];
	++gEbLossN;
}

void EarlyBallNoteOrder(const CCircuitDef@ o)
{
	if (!EarlyBallOn() || (o is null) || Catalog::gBuilder[int(o.id)])
		return;
	const int d = int(o.id);
	if (Air::IsLookDef(d))
		++gEbScoutBuys;
	const int i = gEbOrdDef.find(d);
	if (i < 0) {
		gEbOrdDef.insertLast(d);
		gEbOrdN.insertLast(1);
	} else {
		++gEbOrdN[i];
	}
}

// What the factory draw saw for a def, for the minute line.
void EarlyBallNoteCand(int d, float pc, float p, float mul, float cov)
{
	if (int(gEbLastAt.length()) <= Catalog::gDefCount) {
		gEbLastAt.resize(Catalog::gDefCount + 1);
		gEbLastPc.resize(Catalog::gDefCount + 1);
		gEbLastP.resize(Catalog::gDefCount + 1);
		gEbLastMul.resize(Catalog::gDefCount + 1);
		gEbLastCov.resize(Catalog::gDefCount + 1);
	}
	gEbLastAt[d] = ai.frame;
	gEbLastPc[d] = pc;
	gEbLastP[d] = p;
	gEbLastMul[d] = mul;
	gEbLastCov[d] = cov;
}

float gEbPrev = 0.f;
string EbF(const string &in tag, float now)
{
	const string s = " " + tag + "=" + NnF((gEbPrev > 0.f) ? (now / gEbPrev) : 0.f, 2);
	gEbPrev = now;
	return s;
}

bool EarlyBallPpcDue(int facId)
{
	if (!EarlyBallOn())
		return false;
	const int i = gEbPpcFac.find(facId);
	if (i < 0) {
		gEbPpcFac.insertLast(facId);
		gEbPpcNext.insertLast(ai.frame + 60 * SECOND);
		return true;
	}
	if (ai.frame < gEbPpcNext[i])
		return false;
	gEbPpcNext[i] = ai.frame + 60 * SECOND;
	return true;
}

// UnitPPC's factors one by one, against the line's best core; sq is the core with a second
// division by relative cost (the square law's per-metal index), for comparison only.
string EarlyBallPpcParts(int d, float linePPC)
{
	WorthMeans();
	const float core = UnitCore(d);
	const float rng = 1.f + ((gWMRng > 0.f) ? (Catalog::gMaxRange[d] / gWMRng) : 0.f)
			* ai.GetTunable("apex_range_worth", TUNE_RANGE_WORTH) * ShieldShare();
	float hpd = 1.f;
	{
		const float wHp = ai.GetTunable("apex_worth_hp", TUNE_WORTH_HP);
		const float relHp = (gWMHp > 0.f) ? (Catalog::gHealth[d] / gWMHp) : 0.f;
		if ((wHp != 0.f) && (relHp > 1.f)) {
			float keep = ShieldShare();
			const float cap = FoeSpeedCap();
			if (cap > 1.f) {
				const float sp = Catalog::gSpeed[d] / cap;
				if (sp > keep)
					keep = (sp > 1.f) ? 1.f : sp;
			}
			float safe = PfOutrangedFrac(d) * keep;
			safe = (safe > 1.f) ? 1.f : safe;
			if (safe > 0.f)
				hpd = 1.f / pow(relHp, wHp * safe);
		}
	}
	const float rel = (gWMCost > 0.f) ? (Catalog::gCostM[d] / gWMCost) : 1.f;
	return " core=" + NnF((linePPC > 0.f) ? core / linePPC : 0.f, 3)
		+ " sq=" + NnF((linePPC > 0.f) ? core / rel / linePPC : 0.f, 3)
		+ " wm=" + NnF(WorthModOf(d), 2) + " hold=" + NnF(HoldModOf(d), 2)
		+ " rng=" + NnF(rng, 2) + " hpd=" + NnF(hpd, 2) + " outr=" + NnF(OutrangeMul(d), 2)
		+ " ftier=" + NnF(FoeTierMul(d), 2) + " otier=" + NnF(OwnTierMul(d), 2)
		+ " rec=" + NnF(RecordMul(d), 2);
}

void EarlyBallUpdate()
{
	if (!EarlyBallOn())
		return;
	if (ai.frame >= gEbAt + 5 * SECOND)
		EbRefresh();
	if (ai.frame < gEbLogAt)
		return;
	gEbLogAt = ai.frame + 60 * SECOND;
	string ord = "";
	for (uint i = 0; i < gEbOrdDef.length(); ++i)
		ord += " " + Catalog::Def(gEbOrdDef[i]).GetName() + "=" + gEbOrdN[i];
	gEbOrdDef.resize(0);
	gEbOrdN.resize(0);
	string worth = "";
	for (uint d = 1; d < gEbLastAt.length(); ++d) {
		if ((gEbLastAt[d] <= 0) || (ai.frame - gEbLastAt[d] > 60 * SECOND))
			continue;
		worth += " " + Catalog::Def(int(d)).GetName() + ":" + NnF(gEbLastPc[d], 2) + "/" + NnF(gEbLastP[d], 2)
			+ "/eb" + NnF(gEbLastMul[d], 2) + "/cov" + NnF(gEbLastCov[d], 2);
	}
	int scouts = 0;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if (Air::IsLookDef(int(d)))
			scouts += gOwnCount[d];
	}
	const string best = (gEbBestDef > 0) ? Catalog::Def(gEbBestDef).GetName() : "-";
	const float bestS = ((gEbBestDef > 0) && (int(gEbDefS.length()) > gEbBestDef)) ? gEbDefS[gEbBestDef] : 0.f;
	AiLog(Factory::T() + "apex: earlyball-stat t=" + ai.teamId
		+ " k=" + NnF(SmallHardK(), 2) + " walk=" + int(gEbWalk) + " Rs=" + NnF(gEbRs, 2)
		+ " armyAt=" + int(gEbArmyAt) + " tow=" + int(gEbTowDps) + "/" + int(gEbTowHp) + "/" + int(gEbTowM)
		+ " com=" + int(gEbComDps) + "/" + int(gEbComHp) + " stake=" + int(gEbStake)
		+ " mph=" + NnF(gEbMph, 3) + " q=" + NnF(gEbQD, 3) + "/" + NnF(gEbQH, 2) + " rate=" + NnF(gEbRate, 2)
		+ " best=" + best + " W=" + NnF(gEbBestW, 2) + " N=" + NnF(gEbBestN, 1) + " s=" + NnF(bestS, 2)
		+ " bar=" + int(gEbBar) + " gathered=" + int(gEbGathered) + "(" + int(gEbGatheredM) + "m)"
		+ " quota=" + int(aiMilitaryMgr.quota.attack)
		+ " sent=" + gEbSentN + "/" + int(gEbSentPow) + "p/" + int(gEbSentM) + "m"
		+ " killM=" + int(gEbKillM) + "/" + gEbKillN + " lossM=" + int(gEbLossM) + "/" + gEbLossN
		+ " scouts=" + scouts + " buys=" + gEbScoutBuys + " unseenM=" + int(gEbScoutV)
		+ " m1=" + NnF(gEbScoutM1, 3) + " spots=" + gEbSpotsUnseen + "/" + gEbSpotsAll
		+ " fieldA=" + int(gEbFieldA / 1000000.f) + "M ourA=" + int(gEbOurFieldA / 1000000.f) + "M"
		+ " | ord:" + ord + " | worth:" + worth);
	gEbSentN = 0;
	gEbSentPow = 0.f;
	gEbSentM = 0.f;
	gEbKillM = 0.f;
	gEbKillN = 0;
	gEbLossM = 0.f;
	gEbLossN = 0;
	gEbScoutBuys = 0;
}

}  // namespace Market
