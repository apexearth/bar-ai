namespace Market {
// The assist want's chosen boss. ITS ID IS KEPT BESIDE IT for the same reason
// the guard ledger keeps ids (see GuardNote): CCircuitUnit is NOCOUNT, so this
// handle is not nulled when the engine destroys the unit, and reading .id off
// it to check whether it is still the right target is itself the crash.
CCircuitUnit@ gAssistTarget = null;
Id gAssistTargetId = -1;

// Which kind of ground the defence auction keeps choosing. Without this the
// only way to tell a forward post from a tower at a mex is to read positions
// out of the log by hand.
int gDefSiteFront = 0;
int gDefSiteAsset = 0;
int gDefSiteRing = 0;
int gDefSiteWall = 0;
int gNextDefSiteLog = 0;
int gNextDefFwdLog = 0;
// EVERY TERM OF THE DEFENCE PRICE, so "why so many turrets" is read rather than
// guessed (apexearth: "what is the connection causing this? We need to not
// guess here").
float gDbgStake = 0.f, gDbgHz = 0.f, gDbgSiege = 0.f, gDbgHazard = 0.f, gDbgCapM = 0.f;
float gDbgShort0 = 0.f, gDbgShort1 = 0.f, gDbgThreat = 0.f, gDbgCover0 = 0.f;
float gDbgCover1 = 0.f;
int gNextDefPriceLog = 0;
int gNextProtEnterLog = 0;
float gDbgFrontBest = 0.f;
int gDbgPulled = 0;   // wall slots stepped back from hot ground this minute
float gDbgAssetBest = 0.f;
float gDbgRingBest = 0.f;
float gDbgWallBest = 0.f;
int gDbgLineN = 0;

//------------------------------------------------------------------------------
// THE GATE CENSUS. Every early exit in the defence pricing path counts how often
// it was REACHED and how often it REFUSED. A gate with seen=0 carries no traffic
// at all -- it is dead code, and without this that is invisible: a gate was
// added to such a path and nothing said so for two whole games. Reported
// cumulatively, so the LAST defgates line in a log is the game-end census.
//------------------------------------------------------------------------------
const int GATE_ASSETS      = 0;
const int GATE_CORE        = 1;
const int GATE_AVAIL       = 2;
const int GATE_CLASS       = 3;
const int GATE_HALF        = 4;
const int GATE_RADAR_GAP   = 5;
const int GATE_RADAR_FRONT = 6;
const int GATE_RADAR_HOT   = 7;
const int GATE_JAM_COVER   = 8;
const int GATE_JAM_ARTY    = 9;
const int GATE_SHLD_ARTY   = 10;
const int GATE_SHLD_FAR    = 11;
const int GATE_SHLD_COVER  = 12;
const int GATE_AA_NOAIR    = 13;
const int GATE_AA_SAT      = 14;
const int GATE_TF_ENOUGH   = 15;
const int GATE_DEF_NOSITE  = 16;
const int GATE_DEF_FILL    = 17;
const int GATE_DEF_TEAM    = 18;
const int GATE_ZERO_GAIN   = 19;
const int GATE_SLOT_MARK   = 20;
const int GATE_SLOT_DEAD   = 21;
const int GATE_FILL_CACHE  = 22;
const int GATE_FILL_FRAME  = 23;
const int GATE_SITE_OFFMAP = 24;
const int GATE_SITE_THREAT = 25;
const int GATE_SITE_STAKE  = 26;
const int GATE_SITE_STOP   = 27;
const int GATE_DEF_ROUTE   = 28;
const int GATE_DEF_OWN     = 32;
const int GATE_SHLD_SAT    = 29;   // appended: renumbering would move every counter
const int GATE_JAM_SITE    = 30;
const int GATE_SITE_BLOCKED = 31;   // the C++ reach veto marked the site
const int GATE_SITE_INTERIOR = 33;   // the executor's no-gun-in-the-interior rule
const int GATE_DEF_OBSOLETE = 34;   // dominated on reach and kill by an affordable gun
const int GATE_DEF_T1LATE  = 35;   // his no-basic-tower-after-T2 rule
const int GATE_N           = 36;

array<int> gGateSeen;
array<int> gGateRef;
int gNextGateLog = 0;

string GateName(int g)
{
	if (g == GATE_ASSETS)      return "assets";
	if (g == GATE_CORE)        return "core.offmap";
	if (g == GATE_AVAIL)       return "cand.avail";
	if (g == GATE_CLASS)       return "cand.class";
	if (g == GATE_HALF)        return "cand.half";
	if (g == GATE_RADAR_GAP)   return "radar.nogap";
	if (g == GATE_RADAR_FRONT) return "radar.pastfront";
	if (g == GATE_RADAR_HOT)   return "radar.hot";
	if (g == GATE_JAM_COVER)   return "jam.covered";
	if (g == GATE_JAM_ARTY)    return "jam.noarty";
	if (g == GATE_SHLD_ARTY)   return "shield.noarty";
	if (g == GATE_SHLD_FAR)    return "shield.far";
	if (g == GATE_SHLD_COVER)  return "shield.covered";
	if (g == GATE_SHLD_SAT)    return "shield.saturated";
	if (g == GATE_AA_NOAIR)    return "aa.noair";
	if (g == GATE_AA_SAT)      return "aa.saturated";
	if (g == GATE_TF_ENOUGH)   return "targfac.enough";
	if (g == GATE_DEF_NOSITE)  return "def.nosite";
	if (g == GATE_DEF_FILL)    return "def.targetfill";
	if (g == GATE_DEF_TEAM)    return "def.teampower";
	if (g == GATE_ZERO_GAIN)   return "def.zerogain";
	if (g == GATE_SLOT_MARK)   return "slot.dangermark";
	if (g == GATE_SLOT_DEAD)   return "slot.nopull";
	if (g == GATE_FILL_CACHE)  return "fill.cached";
	if (g == GATE_FILL_FRAME)  return "fill.framecap";
	if (g == GATE_SITE_OFFMAP) return "site.offmap";
	if (g == GATE_SITE_THREAT) return "site.nothreat";
	if (g == GATE_SITE_STAKE)  return "site.nostake";
	if (g == GATE_SITE_STOP)   return "site.nostop";
	if (g == GATE_DEF_ROUTE)   return "def.route";
	if (g == GATE_DEF_OWN)     return "def.ownfill";
	if (g == GATE_JAM_SITE)    return "jam.nosite";
	if (g == GATE_SITE_BLOCKED) return "site.blocked";
	if (g == GATE_SITE_INTERIOR) return "site.interior";
	if (g == GATE_DEF_OBSOLETE) return "def.obsolete";
	if (g == GATE_DEF_T1LATE)  return "def.t1late";
	return "g" + g;
}

void GateInit()
{
	if (int(gGateSeen.length()) >= GATE_N)
		return;
	gGateSeen.resize(uint(GATE_N));
	gGateRef.resize(uint(GATE_N));
}

bool Gate(int g, bool refuse)
{
	GateInit();
	++gGateSeen[g];
	if (refuse)
		++gGateRef[g];
	return refuse;
}

void LogDefGates()
{
	if (ai.frame < gNextGateLog)
		return;
	gNextGateLog = ai.frame + 60 * SECOND;
	GateInit();
	string live = "";
	string dead = "";
	for (int g = 0; g < GATE_N; ++g) {
		if (gGateSeen[g] == 0) {
			dead += " " + GateName(g);
			continue;
		}
		live += " " + GateName(g) + "=" + gGateRef[g] + "/" + gGateSeen[g];
	}
	AiLog(Factory::T() + "apex: defgates CUMULATIVE t=" + ai.teamId
		+ " (refused/seen; last line of the log is the game-end census)"
		+ live + " | DEAD seen=0:" + ((dead == "") ? " none" : dead));
}

//------------------------------------------------------------------------------
// THE DECOMPOSITION LOG. A tower's price is a product of a dozen independent
// terms, so no single one controls the outcome and every change is a nudge whose
// sign depends on which term happens to be extreme. These record each term
// separately for the winner and the runner-up, so "which term decided it" is a
// grep rather than a guess.
//------------------------------------------------------------------------------
array<float> gDwRaw;     // prevented metal/s at the chosen post, before multipliers
array<float> gDwTtd;     // time-to-defence discount
array<float> gDwT1;      // apex_t1_def_late tier discount
array<float> gDwEff;     // wall-slot cover-per-metal efficiency
array<float> gDwFill;    // TargetFill(have, target)
array<float> gDwTeam;    // mine/team tower power
array<float> gDwVal;     // the Want value that came out of ValueOf
array<float> gDwStake;   // fill terms, as of that def's own last real fill
array<float> gDwCapM;
array<float> gDwHz;
array<float> gDwStop;
array<float> gDwThreat;
array<float> gDwCov0;
array<float> gDwCov1;
array<float> gDwKill;    // PfTowerKill(d)
array<int> gDwSite;      // 0 asset, 1 front, 2 ring, 3 wall
array<int> gWhyDef;      // the defs priced in the CURRENT election
int gDefWhyWins = 0;
int gNextDefWhyLog = 0;
float gDbgStopped = 0.f;

void DwEnsure(int d)
{
	uint n = uint(Catalog::gDefCount + 1);
	if (uint(d) + 1 > n)
		n = uint(d) + 1;
	if (gDwRaw.length() >= n)
		return;
	gDwRaw.resize(n);   gDwTtd.resize(n);    gDwT1.resize(n);
	gDwEff.resize(n);   gDwFill.resize(n);   gDwTeam.resize(n);
	gDwVal.resize(n);   gDwStake.resize(n);  gDwHz.resize(n);  gDwCapM.resize(n);
	gDwStop.resize(n);  gDwThreat.resize(n); gDwCov0.resize(n);
	gDwCov1.resize(n);  gDwKill.resize(n);   gDwSite.resize(n);
}

string DwSiteName(int k)
{
	if (k == 1) return "front";
	if (k == 2) return "ring";
	if (k == 3) return "wall";
	return "asset";
}

// A term the active branch did not use is n/a, never 0: a zero in a product of
// multipliers reads as "this one annihilated the price".
string PkF(float v, uint p)
{
	if (v < 0.f)
		return "n/a";
	return formatFloat(v, "", 0, p);
}

// The terms inside PfTowerKill, READ BACK from what that function stamped as it
// priced this def -- not recomputed here. PfTowerKill has two branches and only
// one of them uses surface DPS and the outrange lift, so recomputing printed the
// wrong branch's terms (and its own reference as 0, which the price can never
// have divided by: it returns 0 outright when the reference is not positive).
string PfKillWhy(int d)
{
	PkEnsure(d);
	if (gPkLin[d] < 0)
		return "never priced";
	const bool lin = (gPkLin[d] > 0);
	return "basis=" + (lin ? "dps " : "surfT ") + PkF(gPkBase[d], 2)
		+ " dps=" + PkF(gPkDps[d], 1)
		+ " xOutr=" + PkF(gPkOutr[d], 3)
		+ " /ref=" + PkF(gPkRef[d], 3)
		+ " xDur=" + PkF(gPkDur[d], 3)
		+ " xTrade=" + PkF(gPkTrade[d], 2)
		+ " =pk" + PkF(gPkOut[d], 2);
}

string DefWhyTerms(int d)
{
	DwEnsure(d);
	return Catalog::Def(d).GetName()
		+ " val=" + formatFloat(gDwVal[d], "", 0, 4)
		+ " raw=" + formatFloat(gDwRaw[d], "", 0, 3)
		+ " [stake=" + formatFloat(gDwStake[d], "", 0, 0)
		+ " cap=" + formatFloat(gDwCapM[d], "", 0, 0)
		+ " hz=" + formatFloat(gDwHz[d], "", 0, 5)
		+ " stopped=" + formatFloat(gDwStop[d], "", 0, 3)
		+ " threat=" + formatFloat(gDwThreat[d], "", 0, 0)
		+ " cover=" + formatFloat(gDwCov0[d], "", 0, 0)
		+ "->" + formatFloat(gDwCov1[d], "", 0, 0) + "]"
		+ " xTtd=" + formatFloat(gDwTtd[d], "", 0, 3)
		+ " xT1late=" + formatFloat(gDwT1[d], "", 0, 3)
		+ " xWallEff=" + formatFloat(gDwEff[d], "", 0, 3)
		+ " xFill=" + formatFloat(gDwFill[d], "", 0, 3)
		+ " xTeamPow=" + formatFloat(gDwTeam[d], "", 0, 3)
		+ " kill=" + formatFloat(gDwKill[d], "", 0, 2)
		+ " (" + PfKillWhy(d) + ")"
		+ " costM=" + int(Catalog::gCostM[d])
		+ " site=" + DwSiteName(gDwSite[d]);
}
// The defence auction's own ranking, so "why did we never build a Pulsar" is
// read rather than argued: every turret this builder could place, with what
// the market thinks it is worth.
// The strongest ground turret any constructor WE OWN could place. Cached on a
// slow tick: it walks every owned def's build list.
float gTeamTowerP = 0.f;
int gTeamTowerAt = -1;

// EVERY GROUND DEFENCE THE TEAM CAN MAKE, not just the asker's own list.
//
// apexearth 2026-08-30, after a day of pricing fixes failed to stop Agitators:
// "you thinking only in terms of that one constructor instead of macro-thinking
// about what defense you want. You let an inferior builder decide what IT
// wants." The auction ranked `Catalog::BuildsOf(unit)`, so a T1 hand compared
// an Agitator against a Guard and a Twin Guard and never against the Cerberus
// the team can actually build -- and `apex: defwhy` showed the consequence
// exactly: `priced=1 RUNNERUP none`, every discount applied, val 0.0000, and it
// won because nothing else was in the list. No multiplier can lose an auction
// of one.
//
// Same walk TeamBestTowerPower already does; it computed a discount from this
// set instead of ranking over it.
array<int> gTeamDefDef;
int gTeamDefAt = -999999;

const array<int>@ TeamDefenceDefs()
{
	if (ai.frame < gTeamDefAt)
		return gTeamDefDef;
	gTeamDefAt = ai.frame + 15 * SECOND;
	gTeamDefDef.resize(0);
	const array<int>@ _own23 = OwnedDefs();
	for (uint _oi23 = 0; _oi23 < _own23.length(); ++_oi23) {
		const uint u = uint(_own23[_oi23]);
		if ((gOwnCount[u] <= 0) || !Catalog::gMobile[int(u)]
			|| !Catalog::gBuilder[int(u)])
			continue;
		const array<int>@ bl = Catalog::BuildsOf(int(u));
		for (uint b = 0; b < bl.length(); ++b) {
			const int bd = bl[b];
			if (!Catalog::gAvailable[bd] || Catalog::gMobile[bd]
				|| Catalog::gFloater[bd] || Catalog::gSub[bd])
				continue;
			if (ProtClassOf(bd) != PROT_DEF)
				continue;
			bool seen = false;
			for (uint q = 0; q < gTeamDefDef.length() && !seen; ++q)
				seen = (gTeamDefDef[q] == bd);
			if (!seen)
				gTeamDefDef.insertLast(bd);
		}
	}
	// PRUNED TO THE BENCHMARK. The auction does not need every tower the team
	// owns in the candidate list -- it needs the BEST one, so an inferior local
	// option can be seen losing to it. Carrying all 8-14 tripled the
	// per-election site walk, and `want.protect` became the largest single
	// spike left in the game (36.6 ms, measured Supreme Isthmus v2.1 minute 31).
	// Keeping the best by cover per metal preserves the macro-demand result --
	// the Agitator still loses to the Cerberus -- at a third of the work, and
	// the asking unit's OWN options are unioned in by the caller regardless.
	int bestD = -1;
	float bestEff = 0.f;
	for (uint q2 = 0; q2 < gTeamDefDef.length(); ++q2) {
		const int td = gTeamDefDef[q2];
		const float cm = Catalog::gCostM[td];
		if (cm <= 1.f)
			continue;
		const float eff = PfTowerKill(td) / cm;
		if (eff > bestEff) {
			bestEff = eff;
			bestD = td;
		}
	}
	if (bestD >= 0) {
		gTeamDefDef.resize(0);
		gTeamDefDef.insertLast(bestD);
	}
	return gTeamDefDef;
}

float TeamBestTowerPower()
{
	if (ai.frame < gTeamTowerAt)
		return gTeamTowerP;
	gTeamTowerAt = ai.frame + 15 * SECOND;
	gTeamTowerP = 0.f;
	const array<int>@ _own24 = OwnedDefs();
	for (uint _oi24 = 0; _oi24 < _own24.length(); ++_oi24) {
		const uint u = uint(_own24[_oi24]);
		if ((gOwnCount[u] <= 0) || !Catalog::gMobile[int(u)]
			|| !Catalog::gBuilder[int(u)])
			continue;
		const array<int>@ bl = Catalog::BuildsOf(int(u));
		for (uint b = 0; b < bl.length(); ++b) {
			const int bd = bl[b];
			if (!Catalog::gAvailable[bd] || Catalog::gMobile[bd])
				continue;
			if (ProtClassOf(bd) != PROT_DEF)
				continue;
			CCircuitDef@ cd = Catalog::Def(bd);
			if ((cd !is null) && (cd.power > gTeamTowerP))
				gTeamTowerP = cd.power;
		}
	}
	return gTeamTowerP;
}

// THE BEST TOWER WE COULD ACTUALLY BUY, not the best one that exists.
//
// TeamBestTowerPower above is the strongest static defence ANY of our builders
// can make. Scaling a light tower's gain by how far short of it it falls was
// meant as deferral -- "don't spend the budget on light towers before the heavy
// gun is ever asked for". But the heavy gun is usually unaffordable, and the
// discount does not know that: measured 2026-09-07, one 12-minute game, the
// WINNING defence candidate carried xTeamPow=0.352 all game while defHave sat
// at 85 metal against a defTarget of 3,356. The deferral never converted into a
// heavy gun; it just deleted two thirds of the defence price, every ask, and
// static defence finished at 1.0% of our metal against BARb's 7.1%
// (apexearth: "can you turn our defense building up some?").
//
// A tower we cannot buy is not an alternative to one we can. Ranking against
// what is affordable NOW leaves the deferral intact exactly when it is real --
// the heavy gun is in reach and the light one would waste the window -- and
// removes it when it is imaginary. DefObsoleteOnArrival already hard-drops a
// candidate that something affordable outclasses, so this is the same
// affordability the file already reasons in.
array<float> gTeamTowerCost;
array<float> gTeamTowerPow;
int gTeamLadderAt = -999999;

void TeamTowerLadder()
{
	if (ai.frame < gTeamLadderAt)
		return;
	gTeamLadderAt = ai.frame + 15 * SECOND;
	gTeamTowerCost.resize(0);
	gTeamTowerPow.resize(0);
	const array<int>@ _own25 = OwnedDefs();
	for (uint _oi25 = 0; _oi25 < _own25.length(); ++_oi25) {
		const uint u = uint(_own25[_oi25]);
		if ((gOwnCount[u] <= 0) || !Catalog::gMobile[int(u)]
			|| !Catalog::gBuilder[int(u)])
			continue;
		const array<int>@ bl = Catalog::BuildsOf(int(u));
		for (uint b = 0; b < bl.length(); ++b) {
			const int bd = bl[b];
			if (!Catalog::gAvailable[bd] || Catalog::gMobile[bd])
				continue;
			if (ProtClassOf(bd) != PROT_DEF)
				continue;
			CCircuitDef@ cd = Catalog::Def(bd);
			if (cd is null)
				continue;
			gTeamTowerCost.insertLast(TowerCostEq(bd));
			gTeamTowerPow.insertLast(cd.power);
		}
	}
}

float TeamBestTowerPowerAffordable(float affordM)
{
	TeamTowerLadder();
	float best = 0.f;
	for (uint i = 0; i < gTeamTowerPow.length(); ++i) {
		if ((affordM > 0.f) && (gTeamTowerCost[i] > affordM))
			continue;
		if (gTeamTowerPow[i] > best)
			best = gTeamTowerPow[i];
	}
	return best;
}

array<int> gDefRankDef;
array<float> gDefRankV;
// Per BUILDER DEF, not one clock for the fleet: a single global throttle
// samples whichever constructor happened to elect, and reads as "the advanced
// constructor never proposes defence" when it simply was not sampled.
array<int> gNextDefRankOf;
// COMPLETED, not won. gDefSiteFront counts auction wins, and a re-election
// counts again; a want whose builder dies or whose site is blocked never
// becomes a standing gun. Placement is Military::OnBorder -- the same ray
// model the front sites are drawn from, so won and built are comparable.
int gFrontTowerBuilt = 0;
int gFrontTowerLost = 0;
int gBackTowerBuilt = 0;
int gBackTowerLost = 0;
float gFrontTowerM = 0.f;
float gBackTowerM = 0.f;
int gNextFrontTowerLog = 0;
// ...and where it stood relative to the PERIMETER, which is the question the
// front/back split cannot answer: a tower can be nowhere near the enemy and
// still be on the outer edge of what we own.
int gRimTowerBuilt = 0;
int gCoreTowerBuilt = 0;
float gRimDSum = 0.f;

void NoteTowerBuilt(const AIFloat3& in at, float costM)
{
	{
		// Judged against the WALL when it is on: the raw rim balloons with
		// every far mex claim, and a tower standing exactly on the wall then
		// reads hundreds of elmos "interior" (measured, first exercise game).
		const bool vsWall = (ai.GetTunable("apex_wall", TUNE_WALL) > 0.f)
				&& WallStands();
		const float rd = vsWall ? WallRimDist(at) : PfRimDist(at);
		gRimDSum += rd;
		// Within half a light tower's reach of the rim counts as ON it.
		if (rd > -Brain::LightTowerRange() * 0.5f)
			++gRimTowerBuilt;
		else
			++gCoreTowerBuilt;
	}
	if (Military::OnBorder(at)) {
		++gFrontTowerBuilt;
		gFrontTowerM += costM;
	} else {
		++gBackTowerBuilt;
		gBackTowerM += costM;
	}
}

void NoteTowerLost(const AIFloat3& in at)
{
	if (Military::OnBorder(at))
		++gFrontTowerLost;
	else
		++gBackTowerLost;
}

void LogFrontTowers()
{
	if (ai.frame < gNextFrontTowerLog)
		return;
	gNextFrontTowerLog = ai.frame + 30 * SECOND;
	AiLog(Factory::T() + "apex: fronttowers built=" + gFrontTowerBuilt
		+ " lost=" + gFrontTowerLost
		+ " standing=" + (gFrontTowerBuilt - gFrontTowerLost)
		+ " m=" + int(gFrontTowerM)
		+ " backBuilt=" + gBackTowerBuilt
		+ " backLost=" + gBackTowerLost
		+ " backStanding=" + (gBackTowerBuilt - gBackTowerLost)
		+ " backM=" + int(gBackTowerM)
		+ " wonFront=" + gDefSiteFront
		+ " wonAsset=" + gDefSiteAsset
		+ " rim=" + gRimTowerBuilt
		+ " core=" + gCoreTowerBuilt
		+ " rimDAvg=" + int(gRimDSum
			/ float((gRimTowerBuilt + gCoreTowerBuilt > 0)
				? (gRimTowerBuilt + gCoreTowerBuilt) : 1))
		+ " closure=" + formatFloat(
			(ai.GetTunable("apex_wall", TUNE_WALL) > 0.f)
				? WallClosureFrac() : ClosureFrac(), "", 0, 2)
		+ " lineFill=" + formatFloat(
			(ai.GetTunable("apex_wall", TUNE_WALL) > 0.f)
				? WallLineFill() : -1.f, "", 0, 2)
		+ " lineSlots=" + ((ai.GetTunable("apex_wall", TUNE_WALL) > 0.f)
				? WallLineSlots() : -1)
		+ " lineFwd=" + formatFloat(WallLineFwd(), "", 0, 2)
		+ " wallSlots=" + PfWallSlotCount());
}

void NoteDefSite(bool isFront, bool isRing, bool isWall)
{
	if (isWall)
		++gDefSiteWall;
	else if (isFront)
		++gDefSiteFront;
	else if (isRing)
		++gDefSiteRing;
	else
		++gDefSiteAsset;
	if (ai.frame < gNextDefSiteLog)
		return;
	gNextDefSiteLog = ai.frame + 60 * SECOND;
	AiLog("apex: defsite front=" + gDefSiteFront + " asset=" + gDefSiteAsset
		+ " ring=" + gDefSiteRing
		+ " wall=" + gDefSiteWall
		+ " lineSpots=" + gDbgLineN
		+ " foeReach=" + formatFloat(Military::FoeReach(), "", 0, 0)
		+ " bestFrontGain=" + formatFloat(gDbgFrontBest, "", 0, 2)
		+ " bestAssetGain=" + formatFloat(gDbgAssetBest, "", 0, 2)
		+ " bestRingGain=" + formatFloat(gDbgRingBest, "", 0, 2)
		+ " bestWallGain=" + formatFloat(gDbgWallBest, "", 0, 2)
		+ " pulled=" + gDbgPulled);
	gDbgPulled = 0;
	gDbgFrontBest = 0.f;
	gDbgAssetBest = 0.f;
	gDbgRingBest = 0.f;
	gDbgWallBest = 0.f;
}
}  // namespace Market
