namespace Military {

// HUNT THEIR ARMY, AND EAT IT (apexearth 2026-10-08, docs/24 section 6). Every
// 30 s the biggest ground army of theirs we can see is weighed against our
// attack squads. NO keeps today's play (the rule); HUNT puts our squads' focus
// on that army -- they gather short of it and go in together once the gathered
// power beats it, the team push's machinery (AttackTask focus). Every decision,
// either pick, is watched for HUNT_S: their metal we killed near the group, ours
// lost there, and the wrecks credited to whoever holds the ground they fell on.
const string NNH_HUNT = "grpM,grpInfl,grpFwd,grpHomeD,grpSpd,grpNet,grpArmed,grpShare,foeMobM,foeGrps,"
	+ "atkPow,atkM,armyM,atkD,atkNearPow,powRatio,str,rezN,cover,push,holdWhy,incoming,minute";
const int HT_NO = 0, HT_HUNT = 1;
const float HUNT_R = 600.f;
const float HUNT_NEAR = 2.f * HUNT_R;
const int HUNT_S = 180;
const int HUNT_LOOK = 4 * SECOND;
const int HUNT_MISS = 3;   // looks in a row without the group: it is dead or out of sight

int gHtNextAt = -1;
int gHtLookAt = 0;
int gHtLogAt = 0;
bool gHtHeader = false;
bool gHtOn = false;
bool gHtGo = false;
int gHtUntil = 0;
int gHtMiss = 0;
int gHtFrom = 0;
int gHtLast = 0;
AIFloat3 gHtPos;
int gHtDecN = 0, gHtHuntN = 0, gHtExN = 0, gHtGoN = 0, gHtGoneN = 0, gHtTimeN = 0, gHtNoGrp = 0, gHtNoArmy = 0;
float gHtArmyM = 0.f, gHtAtkM = 0.f, gHtAtkD = -1.f;

array<int> gHwF;
array<int> gHwOpt;
array<AIFloat3> gHwPos;
array<int> gHwLook;
array<int> gHwMiss;
array<float> gHwGrpM;
array<float> gHwKill;
array<float> gHwKillAll;
array<float> gHwLost;
array<float> gHwWreck;

bool HuntHoldsFocus() { return gHtOn; }

// Our ground army, and the metal and centre of what stands on attack tasks.
void HuntArmyCensus(const AIFloat3& in gp)
{
	float m = 0.f, atk = 0.f, cx = 0.f, cz = 0.f;
	for (uint i = 0; i < gCombatId.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(gCombatId[i]));
		if ((u is null) || (u.circuitDef is null) || u.circuitDef.IsAbleToFly())
			continue;
		const AIFloat3 up = u.GetPos(ai.frame);
		if (!OnMap(up))
			continue;
		const float c = u.circuitDef.costM;
		m += c;
		IUnitTask@ t = u.task;
		if ((t is null) || (t.GetType() != Task::Type::FIGHTER) || (t.GetFightType() != int(Task::FightType::ATTACK)))
			continue;
		atk += c;
		cx += c * up.x;
		cz += c * up.z;
	}
	gHtArmyM = m;
	gHtAtkM = atk;
	gHtAtkD = (atk > 0.f) ? AIFloat3(cx / atk, 0.f, cz / atk).distance2D(gp) : -1.f;
}

// Their biggest GROUND army in sight: mobile armed metal per group (air and
// constructors out), its slowest member's speed, and every group's total.
bool HuntTarget(AIFloat3& out at, float& out gm, float& out slow, float& out tot, int& out nG)
{
	int best = -1;
	gm = 0.f;
	slow = 0.f;
	tot = 0.f;
	nG = 0;
	const int n = aiEnemyMgr.GetEnemyGroupCount();
	for (int g = 0; g < n; ++g) {
		const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(g);
		if (!OnMap(gp))
			continue;
		float m = 0.f, sl = 0.f;
		const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(g);
		for (int k = 0; k < nU; ++k) {
			const int ud = aiEnemyMgr.GetEnemyGroupUnitDef(g, k);
			if ((ud <= 0) || (ud > Catalog::gDefCount) || !Catalog::gMobile[ud] || Catalog::gFlyer[ud]
				|| Catalog::gBuilder[ud] || (Catalog::gPower[ud] <= 1.f))
				continue;
			m += Catalog::gCostM[ud];
			if ((sl <= 0.f) || (Catalog::gSpeed[ud] < sl))
				sl = Catalog::gSpeed[ud];
		}
		if (m <= 0.f)
			continue;
		++nG;
		tot += m;
		if (m > gm) {
			gm = m;
			slow = sl;
			best = g;
			at = gp;
		}
	}
	return best >= 0;
}

// The mobile group nearest p that could have walked there since lookF.
bool HuntTrack(const AIFloat3& in p, int lookF, AIFloat3& out q)
{
	Market::RiskFill();
	const float dt = float(ai.frame - lookF) / float(SECOND);
	int bi = -1;
	float bd = 0.f;
	for (uint g = 0; g < Market::gRkApM.length(); ++g) {
		const float vx = Market::gRkApVx[g], vz = Market::gRkApVz[g];
		const float reach = HUNT_R + 2.f * sqrt(vx * vx + vz * vz) * dt;
		const float d = p.distance2D(AIFloat3(Market::gRkApX[g], 0.f, Market::gRkApZ[g]));
		if ((d <= reach) && ((bi < 0) || (d < bd))) {
			bi = int(g);
			bd = d;
		}
	}
	if (bi < 0)
		return false;
	q = AIFloat3(Market::gRkApX[bi], 0.f, Market::gRkApZ[bi]);
	return true;
}

int HuntRezNear(const AIFloat3& in gp)
{
	int n = 0;
	for (uint i = 0; i < Builder::gRezzerIds.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(Builder::gRezzerIds[i]);
		if ((d is null) || (d.count <= 0))
			continue;
		array<CCircuitUnit@>@ near = ai.GetOwnUnitsOfDef(d, gp, HUNT_NEAR);
		if (near !is null)
			n += int(near.length());
	}
	return n;
}

float HuntNnScore(const array<float>& in st, const array<float>& in f, array<float>& w)
{
	return Market::NnHeadScore(Market::NNH_ON, Market::NNH_STATE, NNH_HUNT, Market::NNH_S, Market::NNH_O,
		Market::NNH_H, Market::NNH_XM, Market::NNH_XS, Market::NNH_W1, Market::NNH_B1, Market::NNH_W2, Market::NNH_B2,
		Market::NNH_WO, Market::NNH_BO, Market::NNH_TRUST, st, f, w);
}

void HuntDecide()
{
	AIFloat3 gp;
	float gm = 0.f, slow = 0.f, tot = 0.f;
	int nG = 0;
	if (!HuntTarget(gp, gm, slow, tot, nG)) {
		++gHtNoGrp;
		return;
	}
	const float atkPow = aiMilitaryMgr.GetAttackPower();
	if (atkPow <= 0.f) {
		++gHtNoArmy;
		return;
	}
	gp.y = ai.GetElevationAt(gp);
	const bool explore = Market::gNnExploreRolled && Market::gNnExplore;
	if (!gHtHeader) {
		gHtHeader = true;
		AiLog("apex: nnhunt-schema v1 state=" + Market::NN_STATE + " hunt=" + NNH_HUNT + " opt=name,w,p opts=NO,HUNT");
	}
	HuntArmyCensus(gp);
	const float infl = aiMilitaryMgr.GetEnemyInflNear(gp, HUNT_R);
	AIFloat3 pushAt;
	float pushR = 0.f;
	array<float> st;
	Market::NnState(null, st);
	array<float> f;
	f.insertLast(gm);
	f.insertLast(infl);
	f.insertLast(ForwardFraction(gp));
	f.insertLast(Builder::gHomeSet ? gp.distance2D(Builder::gHomePos) : -1.f);
	f.insertLast(slow);
	f.insertLast(ai.GetNetInflAt(gp));
	f.insertLast(ai.GetEnemyArmedCostNear(gp, HUNT_NEAR));
	f.insertLast((tot > 0.f) ? gm / tot : 0.f);
	f.insertLast(tot);
	f.insertLast(float(nG));
	f.insertLast(atkPow);
	f.insertLast(gHtAtkM);
	f.insertLast(gHtArmyM);
	f.insertLast(gHtAtkD);
	f.insertLast(aiMilitaryMgr.GetAttackPowerNear(gp, HUNT_NEAR));
	f.insertLast(atkPow / ((infl > 1.f) ? infl : 1.f));
	f.insertLast(Market::StrRatio(gm, gHtAtkM));
	f.insertLast(float(HuntRezNear(gp)));
	f.insertLast(Market::CoverAt(gp));
	f.insertLast(Market::PushGoAt(pushAt, pushR) ? 1.f : 0.f);
	f.insertLast(float(HoldWhy()));
	f.insertLast(PushIncoming() ? 1.f : 0.f);
	f.insertLast(float(ai.frame) / 1800.f);
	array<float> w(2, Market::NE2_EPS);
	w[HT_NO] = 1.f;
	const float trust = HuntNnScore(st, f, w);
	array<float> p(2);
	const int c = Market::EcoDraw(HT_NO, trust, w, p, explore ? 0.5f : 0.f);
	array<string> names = {"NO", "HUNT"};
	AiLog(Market::EcoLine("nnhunt", "NO", explore, trust, st, f, names, w, p, c));
	++gHtDecN;
	if (explore)
		++gHtExN;
	gHwF.insertLast(ai.frame);
	gHwOpt.insertLast(c);
	gHwPos.insertLast(gp);
	gHwLook.insertLast(ai.frame);
	gHwMiss.insertLast(0);
	gHwGrpM.insertLast(gm);
	gHwKill.insertLast(0.f);
	gHwKillAll.insertLast(0.f);
	gHwLost.insertLast(0.f);
	gHwWreck.insertLast(0.f);
	if (c == HT_HUNT)
		HuntStart(gp, gm);
}

void HuntStart(const AIFloat3& in at, float gm)
{
	gHtOn = true;
	gHtGo = false;
	gHtPos = at;
	gHtMiss = 0;
	gHtFrom = ai.frame;
	gHtLast = ai.frame;
	gHtUntil = ai.frame + HUNT_S * SECOND;
	++gHtHuntN;
	AiLog(Factory::T() + "apex: hunt start t=" + ai.teamId + " at=" + int(at.x) + "," + int(at.z)
		+ " grpM=" + int(gm) + " atkPow=" + Market::NnF(aiMilitaryMgr.GetAttackPower(), 1));
	HuntFocus();
}

// Gather short of the group, then go once what has gathered beats it.
void HuntFocus()
{
	AIFloat3 fp = gHtPos;
	fp.y = ai.GetElevationAt(fp);
	const float foe = aiMilitaryMgr.GetEnemyInflNear(fp, HUNT_R + Market::PUSH_STAND);
	float mine = aiMilitaryMgr.GetGatheredPower();
	if (!gHtGo && (mine > 0.f) && (mine > foe)) {
		gHtGo = true;
		++gHtGoN;
		AiLog(Factory::T() + "apex: hunt go t=" + ai.teamId + " at=" + int(fp.x) + "," + int(fp.z)
			+ " foe=" + Market::NnF(foe, 1) + " mine=" + Market::NnF(mine, 1)
			+ " s=" + ((ai.frame - gHtFrom) / SECOND));
	}
	if (gHtGo)
		mine = aiMilitaryMgr.GetAttackPowerNear(fp, HUNT_NEAR);
	aiMilitaryMgr.SetFocus(fp, HUNT_R, mine, gHtGo, ai.frame + 10 * SECOND);
}

void HuntEnd(const string why)
{
	gHtOn = false;
	aiMilitaryMgr.SetFocus(AIFloat3(0.f, 0.f, 0.f), 0.f, 0.f, false, -1);
	if (why == "gone")
		++gHtGoneN;
	else
		++gHtTimeN;
	AiLog(Factory::T() + "apex: hunt end t=" + ai.teamId + " why=" + why + " go=" + (gHtGo ? 1 : 0)
		+ " s=" + ((ai.frame - gHtFrom) / SECOND));
}

void HuntLook()
{
	if (gHtOn) {
		AIFloat3 hp;
		if (HuntTrack(gHtPos, gHtLast, hp)) {
			gHtPos = hp;
			gHtMiss = 0;
		} else {
			++gHtMiss;
		}
		gHtLast = ai.frame;
		if (gHtMiss >= HUNT_MISS)
			HuntEnd("gone");
		else if (ai.frame >= gHtUntil)
			HuntEnd("time");
		else
			HuntFocus();
	}
	for (int i = int(gHwF.length()) - 1; i >= 0; --i) {
		if (ai.frame < gHwF[i] + HUNT_S * SECOND) {
			AIFloat3 wp;
			if (HuntTrack(gHwPos[i], gHwLook[i], wp)) {
				gHwPos[i] = wp;
				gHwMiss[i] = 0;
			} else {
				++gHwMiss[i];
			}
			gHwLook[i] = ai.frame;
			continue;
		}
		const float k = gHwKill[i], l = gHwLost[i], wr = gHwWreck[i];
		const float den = k + l + gHwGrpM[i];
		const float score = (k + wr - l) / ((den > 1.f) ? den : 1.f);
		AiLog("apex: nnhunt-done t=" + ai.teamId + " f=" + gHwF[i] + " opt=" + gHwOpt[i]
			+ " done=" + Market::NnF(score, 4) + " kill=" + int(k) + " killAll=" + int(gHwKillAll[i])
			+ " lost=" + int(l) + " wreck=" + int(wr) + " grpM=" + int(gHwGrpM[i]) + " miss=" + gHwMiss[i]);
		gHwF.removeAt(i);
		gHwOpt.removeAt(i);
		gHwPos.removeAt(i);
		gHwLook.removeAt(i);
		gHwMiss.removeAt(i);
		gHwGrpM.removeAt(i);
		gHwKill.removeAt(i);
		gHwKillAll.removeAt(i);
		gHwLost.removeAt(i);
		gHwWreck.removeAt(i);
	}
}

// A death near a watched group: theirs is a kill, ours a loss, and half its
// metal is a wreck for whoever holds that ground.
void HuntNoteDeath(const AIFloat3& in pos, float m, bool ours, bool byUs)
{
	if ((gHwF.length() == 0) || (m <= 0.f) || !OnMap(pos))
		return;
	bool read = false;
	float side = 0.f;
	for (uint i = 0; i < gHwF.length(); ++i) {
		if (pos.distance2D(gHwPos[i]) > HUNT_NEAR)
			continue;
		if (!read) {
			read = true;
			const float net = ai.GetNetInflAt(pos);
			side = (net > 0.f) ? 0.5f : ((net < 0.f) ? -0.5f : 0.f);
		}
		if (ours) {
			gHwLost[i] += m;
		} else {
			gHwKillAll[i] += m;
			if (byUs)
				gHwKill[i] += m;
		}
		gHwWreck[i] += side * m;
	}
}

void UpdateHunt()
{
	if (!Builder::gHomeSet)
		return;
	if (gHtNextAt < 0)
		gHtNextAt = 60 * SECOND + (ai.teamId % 15) * 2 * SECOND;
	if (ai.frame >= gHtLookAt) {
		gHtLookAt = ai.frame + HUNT_LOOK;
		HuntLook();
	}
	if (!gHtOn && (ai.frame >= gHtNextAt)) {
		gHtNextAt = ai.frame + 30 * SECOND;
		HuntDecide();
	}
	if (ai.frame >= gHtLogAt) {
		gHtLogAt = ai.frame + 60 * SECOND;
		if (gHtDecN + gHtNoGrp + gHtNoArmy > 0)
			AiLog(Factory::T() + "apex: hunt-stat t=" + ai.teamId + " dec=" + gHtDecN + " ex=" + gHtExN
				+ " hunt=" + gHtHuntN + " go=" + gHtGoN + " gone=" + gHtGoneN + " time=" + gHtTimeN
				+ " noGrp=" + gHtNoGrp + " noArmy=" + gHtNoArmy + " on=" + (gHtOn ? 1 : 0)
				+ " watch=" + gHwF.length());
	}
}

}  // namespace Military
