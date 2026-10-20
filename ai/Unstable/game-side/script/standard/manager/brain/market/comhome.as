namespace Market {

// THE COMMANDER STAYS HOME ON A SMALL MAP (his 2026-10-16: "stay supporting the factory and
// building more army ... don't just lose them straight to the enemy commander"). apex_com_home.
//   w     = SmallHardComArmyW() = contact k x army gap share (0 on a large map, or army at target)
//   lathe = his BP x 7/80 x energy feed, at most income + bank/60: what his pull at the lab makes army
//   away  = w x lathe x (walk to the job + its build + walk on to the lab - walk to the lab now),
//           charged on every commander job but the lab guard; the guard earns w x lathe
//   pD    = 1 - after / COM_BOLD_BUFFER on [0,1]: the fight estimate's measured error band
//   home  : their commanders are ground army; he defends while k x stake x (1 - pD) > pD x worth
//   walk  : the D-gun walk-in in peace pays pD x worth at its target, seen guns and their unseen
//           commanders counted, against the metal it can take

bool gCmhOn = false;
bool gCmhRead = false;
bool ComHomeOn()
{
	if (!gCmhRead) {
		gCmhRead = true;
		gCmhOn = ai.GetTunable("apex_com_home", TUNE_COM_HOME) > 0.f;
	}
	return gCmhOn;
}

float ComHomeWorthM() { return gAssetsM + ArmyValue(); }

float ComHomeDeathP(float after)
{
	const float p = 1.f - after / COM_BOLD_BUFFER;
	return (p < 0.f) ? 0.f : ((p > 1.f) ? 1.f : p);
}

// Their fire while he kills m of them one after another: (m+1)/2m of full, 1 against one.
float ComHomeFire(float m)
{
	return (m > 1.f) ? (m + 1.f) / (2.f * m) : 1.f;
}

// The D-gun does no damage to a commander (BAR weapondefs: commanders = 0).
bool ComHomeDgKills(int d)
{
	return !ComHomeOn() || !Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask);
}

float ComHomeLathe(CCircuitUnit@ u)
{
	const int uid = int(u.circuitDef.id);
	float eFeed = 1.f;
	const float eInc = Eco::EInc();
	const float ePull = Eco::EPull();
	if ((ePull > 1.f) && (eInc < ePull))
		eFeed = eInc / ePull;
	const float lathe = Catalog::gBuildPower[uid] * (7.f / 80.f) * eFeed;
	const float feed = Eco::MInc() + Eco::MCur() / 60.f;
	return (lathe < feed) ? lathe : feed;
}

int gCmhLabAt = -1;
CCircuitUnit@ gCmhLab = null;
CCircuitUnit@ ComHomeLab(const AIFloat3& in me)
{
	if (gCmhLabAt == ai.frame)
		return gCmhLab;
	gCmhLabAt = ai.frame;
	@gCmhLab = null;
	float best = 0.f;
	for (uint i = 0; i < Brain::gFQFac.length(); ++i) {
		CCircuitUnit@ f = Brain::gFQFac[i];
		if ((f is null) || (f.CountQueued(null) <= 0))
			continue;
		const float d2 = me.SqDistance2D(f.GetPos(ai.frame));
		if ((gCmhLab is null) || (d2 < best)) {
			best = d2;
			@gCmhLab = f;
		}
	}
	return gCmhLab;
}

int gCmhAwayN = 0;
float gCmhAwaySum = 0.f;
double gCmhAwayUs = 0.0, gCmhAwayUsMax = 0.0;
float ComHomeAwayM(CCircuitUnit@ unit, Want@ w)
{
	if (!ComHomeOn() || (w is null) || !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return 0.f;
	const float wgt = SmallHardComArmyW();
	if (wgt <= 0.f)
		return 0.f;
	const double t0 = ai.ClockUs();
	const AIFloat3 me = unit.GetPos(ai.frame);
	CCircuitUnit@ lab = ComHomeLab(me);
	const float spd = Catalog::gSpeed[int(unit.circuitDef.id)];
	float m = 0.f;
	if ((lab !is null) && (spd > 1.f) && !((w.kind == WK_ASSIST) && (w.spotId == int(lab.id)))) {
		const AIFloat3 lp = lab.GetPos(ai.frame);
		float build = w.buildSec;
		if ((build <= 0.f) && (w.assistEcoS > 0))
			build = float(w.assistEcoS);
		const float delay = (me.distance2D(w.pos) + w.pos.distance2D(lp) - me.distance2D(lp)) / spd + build;
		if (delay > 0.f)
			m = wgt * ComHomeLathe(unit) * delay;
	}
	const double us = ai.ClockUs() - t0;
	gCmhAwayUs += us;
	if (us > gCmhAwayUsMax)
		gCmhAwayUsMax = us;
	++gCmhAwayN;
	gCmhAwaySum += m;
	return m;
}

// THE BASE UNDER ATTACK. Their commanders in group g, in metal (GroundArmyOf skips builders).
float ComHomeComM(int g)
{
	if (!ComHomeOn())
		return 0.f;
	float m = 0.f;
	const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(g);
	for (int k = 0; k < nU; ++k) {
		const int d = aiEnemyMgr.GetEnemyGroupUnitDef(g, k);
		if (Catalog::ValidId(d) && Catalog::gMobile[d] && !Catalog::gFlyer[d] && (Catalog::gSurfDps[d] > 0.f)
			&& Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask))
			m += Catalog::gCostM[d];
	}
	return m;
}

// His fight against group g at `at` with the guns and army there: the health it leaves him.
float ComHomeGroupAfter(CCircuitUnit@ u, int g, const AIFloat3& in at)
{
	const int cd = int(u.circuitDef.id);
	float dps = 0.f, hpS = 0.f, vmax = 0.f, rad = 0.f;
	int n = 0, nk = 0;
	const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(g);
	for (int k = 0; k < nU; ++k) {
		const int d = aiEnemyMgr.GetEnemyGroupUnitDef(g, k);
		if (!Catalog::ValidId(d) || !Catalog::gMobile[d] || Catalog::gFlyer[d] || (Catalog::gSurfDps[d] <= 0.f))
			continue;
		++n;
		dps += Catalog::gSurfDps[d];
		hpS += Catalog::gHealth[d];
		if (Catalog::gSpeed[d] > vmax)
			vmax = Catalog::gSpeed[d];
		if (ComHomeDgKills(d)) {
			++nk;
			rad += 4.f * float((Catalog::gFootX[d] > Catalog::gFootZ[d]) ? Catalog::gFootX[d] : Catalog::gFootZ[d]);
		}
	}
	const float hp = u.GetHealthPercent();
	if (n <= 0)
		return hp;
	float gd = 0.f, gh = 0.f, ad = 0.f, ah = 0.f, s = 0.f;
	ComGunAt(at, gd, gh);
	ComArmyAt(at, ai.GetTunable("apex_threat_r", TUNE_THREAT_R), ad, ah);
	ComFightHpAfter(hp, Catalog::gHealth[cd], Catalog::gSurfDps[cd], gd + ad, gh + ah, dps, hpS, 0.f, n, s);
	const float kills = ComDGunKills(u, s, vmax, (nk > 0) ? rad / float(nk) : 12.f, nk);
	return ComFightHpAfter(hp, Catalog::gHealth[cd], Catalog::gSurfDps[cd], gd + ad, gh + ah, dps, hpS, kills, n, s);
}

int gCmhShipPriced = 0, gCmhShipDefend = 0;
float gCmhShipStake = 0.f, gCmhShipPD = 0.f;
// Called by ComShipAssess once it has its verdict: a hopeless base is still defended
// while what stands there outweighs his expected death.
void ComHomeShip(CCircuitUnit@ u)
{
	if (!ComHomeOn() || !gShipHopeless || (gShipG < 0) || !OnMap(gShipAt))
		return;
	const float k = SmallHardK();
	if (k <= 0.f)
		return;
	++gCmhShipPriced;
	gCmhShipStake = StakeAt(gShipAt, ai.GetTunable("apex_threat_r", TUNE_THREAT_R));
	gCmhShipPD = ComHomeDeathP(ComHomeGroupAfter(u, gShipG, gShipAt));
	if (k * gCmhShipStake * (1.f - gCmhShipPD) > gCmhShipPD * ComHomeWorthM()) {
		gShip = true;
		gShipHopeless = false;
		++gCmhShipDefend;
	}
}

// Home is the threatened side: his retreat goes home, not a step aside.
bool ComHomeRetreatHome()
{
	return ComHomeOn() && (gShipHome > 0) && (SmallHardK() > 0.f);
}

// THE D-GUN WALK-IN IN PEACE (4.2-4.7 m: six shots at a Construction Kbot, none in the beam,
// walked him to fwd 0.84 and a Light Laser Tower he never counted).
int gCmhWalkAt = -1;
bool gCmhWalkOk = true;
int gCmhWalkAsk = 0, gCmhWalkNo = 0;
bool ComHomeWalkOk(CCircuitUnit@ u)
{
	if (!ComHomeOn())
		return true;
	if (gCmhWalkAt == ai.frame)
		return gCmhWalkOk;
	gCmhWalkAt = ai.frame;
	gCmhWalkOk = true;
	float mult = ai.GetTunable("apex_dgun_close_mult", TUNE_DGUN_CLOSE_MULT);
	if (mult < 1.f)
		mult = 1.f;
	const float reach = u.DGunRange() * mult;
	const AIFloat3 here = u.GetPos(ai.frame);
	float prize = 0.f, nearD = -1.f;
	AIFloat3 at;
	const int nG = aiEnemyMgr.GetEnemyGroupCount();
	for (int gi = 0; gi < nG; ++gi) {
		const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(gi);
		if (!OnMap(gp))
			continue;
		const float d = gp.distance2D(here);
		if (d > reach)
			continue;
		prize += aiEnemyMgr.GetEnemyGroupCost(gi);
		if ((nearD < 0.f) || (d < nearD)) {
			nearD = d;
			at = gp;
		}
	}
	if (nearD < 0.f)
		return true;
	++gCmhWalkAsk;
	ComRaidFill(u);
	float pD = 1.f;
	if (!gCrHome) {
		bool heavy = false;
		const float after = ComClaimHpAfter(u, at, heavy);
		pD = heavy ? 1.f : ComHomeDeathP(after);
	}
	gCmhWalkOk = prize * (1.f - pD) > pD * ComHomeWorthM();
	if (!gCmhWalkOk)
		++gCmhWalkNo;
	return gCmhWalkOk;
}

// apex: comhome-stat, once a minute while he lives (both arms: the A/B reads it).
array<int> gCmhJobS = {0, 0, 0, 0, 0, 0, 0, 0};   // assist, mex, eco, plant, def, fight, retreat, other
array<int> gCmhFwdS = {0, 0, 0, 0};                // fwd < .25, < .5, < .75, beyond
int gCmhHomeS = 0, gCmhHomeHereS = 0, gCmhHomeShipS = 0, gCmhHomeRunS = 0;
int gCmhAlt = 0, gCmhFrAt = -999999, gCmhFrDec = -1;
int gCmhElec = 0, gCmhGuardSeen = 0, gCmhGuardWon = 0;
float gCmhGuardVSum = 0.f, gCmhWinVSum = 0.f;
float gCmhGuardV = 0.f;
int gCmhGuardAt = -1;
int gCmhLogAt = 60 * SECOND;

void ComHomeNoteGuard(float v)
{
	gCmhGuardV = v;
	gCmhGuardAt = ai.frame;
}

void ComHomeNoteElection(CCircuitUnit@ unit, Want@ top)
{
	if ((top is null) || !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return;
	++gCmhElec;
	gCmhWinVSum += top.value;
	if (ai.frame - gCmhGuardAt <= 2 * SECOND) {
		++gCmhGuardSeen;
		gCmhGuardVSum += gCmhGuardV;
		if (top.kind == WK_ASSIST)
			++gCmhGuardWon;
	}
}

// FIGHT and RETREAT swapping inside 10 s.
void ComHomeNoteDec(int was, int now)
{
	if (((now == COM_FIGHT) || (now == COM_RETREAT)) && (now != was)) {
		if ((gCmhFrDec >= 0) && (gCmhFrDec != now) && (ai.frame - gCmhFrAt < 10 * SECOND))
			++gCmhAlt;
		gCmhFrDec = now;
		gCmhFrAt = ai.frame;
	}
}

void ComHomeTick(CCircuitUnit@ u, int job)
{
	++gCmhJobS[job];
	const AIFloat3 here = u.GetPos(ai.frame);
	const float f = Military::ForwardFraction(here);
	++gCmhFwdS[(f < 0.25f) ? 0 : ((f < 0.5f) ? 1 : ((f < 0.75f) ? 2 : 3))];
	if (gShipHome > 0) {
		++gCmhHomeS;
		if (Builder::gHomeSet && (here.distance2D(Builder::gHomePos) <= Builder::BASE_DANGER_DIST)
			&& (f <= Military::FWD_HOME))
			++gCmhHomeHereS;
		if (gShip)
			++gCmhHomeShipS;
		else if (gComDec == COM_RETREAT)
			++gCmhHomeRunS;
	}
	if (ai.frame < gCmhLogAt)
		return;
	gCmhLogAt = ai.frame + 60 * SECOND;
	string jobs = "";
	for (uint i = 0; i < gCmhJobS.length(); ++i) {
		jobs += ((i == 0) ? "" : ",") + SH_JOBS[i] + "=" + gCmhJobS[i];
		gCmhJobS[i] = 0;
	}
	string fwd = "";
	for (uint i = 0; i < gCmhFwdS.length(); ++i) {
		fwd += ((i == 0) ? "" : "/") + gCmhFwdS[i];
		gCmhFwdS[i] = 0;
	}
	const float gs = float((gCmhGuardSeen > 0) ? gCmhGuardSeen : 1);
	const float es = float((gCmhElec > 0) ? gCmhElec : 1);
	const float an = float((gCmhAwayN > 0) ? gCmhAwayN : 1);
	AiLog(Factory::T() + "apex: comhome-stat t=" + ai.teamId + " on=" + (ComHomeOn() ? 1 : 0)
		+ " k=" + formatFloat(SmallHardK(), "", 0, 2) + " w=" + formatFloat(SmallHardComArmyW(), "", 0, 2)
		+ " lathe=" + formatFloat(ComHomeLathe(u), "", 0, 1)
		+ " jobS=" + jobs + " fwdS=" + fwd
		+ " elec=" + gCmhElec + " guard=" + gCmhGuardSeen + "/won" + gCmhGuardWon
		+ " guardV=" + formatFloat(gCmhGuardVSum * 1000.f / gs, "", 0, 2)
		+ " winV=" + formatFloat(gCmhWinVSum * 1000.f / es, "", 0, 2)
		+ " away=" + gCmhAwayN + "x" + formatFloat(gCmhAwaySum / an, "", 0, 0)
		+ " awayUs=" + formatFloat(float(gCmhAwayUs) / an, "", 0, 1) + "/" + int(gCmhAwayUsMax)
		+ " homeS=" + gCmhHomeS + " here=" + gCmhHomeHereS + " ship=" + gCmhHomeShipS + " run=" + gCmhHomeRunS
		+ " shipPriced=" + gCmhShipPriced + "/" + gCmhShipDefend
		+ " stake=" + int(gCmhShipStake) + " pD=" + formatFloat(gCmhShipPD, "", 0, 2)
		+ " walk=" + gCmhWalkAsk + "/no" + gCmhWalkNo
		+ " alt=" + gCmhAlt);
	gCmhElec = 0;
	gCmhGuardSeen = 0;
	gCmhGuardWon = 0;
	gCmhGuardVSum = 0.f;
	gCmhWinVSum = 0.f;
	gCmhAwayN = 0;
	gCmhAwaySum = 0.f;
	gCmhAwayUs = 0.0;
	gCmhAwayUsMax = 0.0;
	gCmhHomeS = 0;
	gCmhHomeHereS = 0;
	gCmhHomeShipS = 0;
	gCmhHomeRunS = 0;
	gCmhShipPriced = 0;
	gCmhShipDefend = 0;
	gCmhWalkAsk = 0;
	gCmhWalkNo = 0;
	gCmhAlt = 0;
}

}  // namespace Market
