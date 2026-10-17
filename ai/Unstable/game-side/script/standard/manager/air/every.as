namespace Air {

// apex_air_every (docs/tunables.md): every seat's air plant priced by what it yields, the wing launched on the
// planes it has, fighters bought and flown against the enemy air we see.
int gEvOn = -1;
bool EveryOn()
{
	if (gEvOn < 0)
		gEvOn = (ai.GetTunable("apex_air_every", TUNE_AIR_EVERY) > 0.f) ? 1 : 0;
	return gEvOn > 0;
}

// their aircraft as we know them, seen or remembered
int gEvSnapAt = -1000000;
float gEvFoeAirM = 0.f, gEvFoeFtrM = 0.f, gEvFoeStrM = 0.f;
float gEvFoeFtrHp = 0.f, gEvFoeFtrDps = 0.f, gEvFoeStrHp = 0.f, gEvFoeSpd = 0.f;

void EvSnapFoeAir()
{
	if ((gEvSnapAt >= 0) && (ai.frame - gEvSnapAt < 5 * SECOND))
		return;
	gEvSnapAt = ai.frame;
	gEvFoeAirM = 0.f; gEvFoeFtrM = 0.f; gEvFoeStrM = 0.f;
	gEvFoeFtrHp = 0.f; gEvFoeFtrDps = 0.f; gEvFoeStrHp = 0.f;
	float spd = 0.f;
	int n = 0;
	const int total = aiEnemyMgr.GetEnemyUnitTotal();
	for (int i = 0; i < total; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d <= 0) || (d > Catalog::gDefCount))
			continue;
		if (!Catalog::gFlyer[d] || !Catalog::gMobile[d] || Catalog::gBuilder[d] || (Catalog::gPower[d] <= 1.f))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			continue;
		const float m = Catalog::gCostM[d];
		gEvFoeAirM += m;
		const float a = NaAirDps(d);
		if (a > 0.f) {
			gEvFoeFtrM += m;
			gEvFoeFtrHp += Catalog::gHealth[d];
			gEvFoeFtrDps += a;
		} else {
			gEvFoeStrM += m;
			gEvFoeStrHp += Catalog::gHealth[d];
		}
		spd += Catalog::gSpeed[d];
		++n;
	}
	gEvFoeSpd = (n > 0) ? spd / float(n) : 0.f;
}

// Their strike planes' flight from their side to our home: the time our fighters have to kill them.
float EvFoeFlightS()
{
	if (!Builder::gHomeSet || (gEvFoeSpd <= 0.f))
		return 0.f;
	const AIFloat3 foe = NaFoe();
	if (!OnMap(foe))
		return 0.f;
	return foe.distance2D(Builder::gHomePos) / gEvFoeSpd;
}

// The metal of fighter f that answers their air: enough to win the square-law fight against their fighters,
// and enough air dps to kill their bombers and gunships inside their flight to us.
float EvFighterWantM(int f)
{
	if ((f <= 0) || (f > Catalog::gDefCount))
		return 0.f;
	EvSnapFoeAir();
	const float hp = Catalog::gHealth[f];
	const float dps = NaAirDps(f);
	const float c = Catalog::gCostM[f];
	if ((hp <= 0.f) || (dps <= 0.f) || (c <= 0.f))
		return 0.f;
	float n = sqrt(gEvFoeFtrHp * gEvFoeFtrDps / (hp * dps));
	const float tau = EvFoeFlightS();
	if ((tau > 0.f) && (gEvFoeStrHp > 0.f)) {
		const float nK = gEvFoeStrHp / (tau * dps);
		if (nK > n)
			n = nK;
	}
	return n * c;
}

float EvFighterHaveM()
{
	float have = FighterMetalHeld();
	for (int pass = 0; pass < 2; ++pass) {
		CCircuitDef@ fd = (pass == 0) ? gFighter : gFighter1;
		if (fd !is null)
			have += float(Brain::PendAnyOf(int(fd.id))) * Catalog::gCostM[int(fd.id)];
	}
	return have;
}

float EvFighterShare()
{
	const float team = Military::TeamArmyCost();
	const float mine = aiMilitaryMgr.armyCost;
	return (team > mine && team > 1.f) ? (mine / team) : 1.f;
}

// The production price of one more fighter of def d: the shortfall against their air, over the fill window.
float EveryFighterGainFor(int d, float fillSec)
{
	if (!IsFighterDef(d))
		return 0.f;
	const float want = EvFighterWantM(d) * EvFighterShare();
	const float have = EvFighterHaveM();
	if (want <= have)
		return 0.f;
	return (want - have) / ((fillSec > 1.f) ? fillSec : 180.f);
}

// The escort the held wing waits for: its own bombers at the wing's ratio, not the wing it might grow into.
int EvEscortWant()
{
	return (HeldBombers() * AIR_FIGHTERS + AIR_BOMBERS - 1) / AIR_BOMBERS;
}

// A hunt flight launches whole: the fighters at home past the escort go together once they beat the fighters
// of theirs we know of; one finished later waits for the next flight.
int gEvHuntLaunch = 0, gEvHuntHold = 0, gEvHuntN = 0;
string gEvHuntWhy = "-";

int gEvHuntNoAt = -1000000;

bool EvHuntLaunch(CCircuitUnit@ unit)
{
	if (ai.frame - gEvHuntNoAt < SECOND)
		return false;
	gEvHuntNoAt = ai.frame;
	if (aiEnemyMgr.GetEnemyCostFresh(RT::AIR) <= 0.f) {
		gEvHuntWhy = "noair";
		return false;
	}
	EvSnapFoeAir();
	HuntPrune();
	array<CCircuitUnit@> cand;
	cand.insertLast(unit);
	for (int pass = 0; pass < 2; ++pass) {
		CCircuitDef@ fd = (pass == 0) ? gFighter : gFighter1;
		if (fd is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(fd, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			CCircuitUnit@ u = us[k];
			if ((u is null) || (u.id == unit.id) || InWave(u.id) || Covering(u.id)
				|| (FlightOutIdx(u.id) >= 0) || InList(gHunters, u.id))
				continue;
			cand.insertLast(u);
		}
	}
	const int surplus = int(cand.length()) - EvEscortWant();
	if (surplus <= 0) {
		gEvHuntWhy = "escort";
		return false;
	}
	float hp = 0.f, dps = 0.f;
	for (int k = 0; k < surplus; ++k) {
		const int d = int(cand[k].circuitDef.id);
		hp += Catalog::gHealth[d];
		dps += NaAirDps(d);
	}
	if (hp * dps < gEvFoeFtrHp * gEvFoeFtrDps) {
		++gEvHuntHold;
		gEvHuntWhy = "outmatched";
		return false;
	}
	for (int k = 0; k < surplus; ++k)
		gHunters.insertLast(cand[k].id);
	gEvHuntNoAt = -1000000;
	++gEvHuntLaunch;
	gEvHuntN += surplus;
	gEvHuntWhy = "launch";
	AiLog(Factory::T() + "apex: airevery hunt t=" + ai.teamId + " n=" + surplus
		+ " ours=" + int(sqrt(hp * dps)) + " theirs=" + int(sqrt(gEvFoeFtrHp * gEvFoeFtrDps))
		+ " foeAir=" + int(gEvFoeAirM));
	return true;
}

// THE PLANT'S YIELD. What its strike planes net against the AA we know, per bomber or gunship type: the
// smallest wing that finishes the best cell and comes out ahead, priced over the time this plant takes to
// build that wing. Filled on nnair's demand clock.
array<int> gEvPlantDef(2, -1);
array<float> gEvPlantV(2, 0.f);
array<int> gEvPlantN(2, 0);
array<int> gEvPlantUnit(2, -1);

void EvDemandStep(float fillSec)
{
	if (!EveryOn())
		return;
	ResolveDefs();
	const AIFloat3 foe = NaFoe();
	if (!OnMap(foe) || !Builder::gHomeSet)
		return;
	NaSnapEnemy(foe);
	const float r = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R);
	gNaKeyD = 0.f;
	array<NaCand@> cs;
	NaCands(r, cs);
	const AIFloat3 from = Builder::gHomePos;
	array<float> pAA(cs.length());
	for (uint i = 0; i < cs.length(); ++i)
		pAA[i] = NaPathAA(from, cs[i].at);
	const float fs = (fillSec > 1.f) ? fillSec : 180.f;
	for (int pk = 0; pk < 2; ++pk) {
		CCircuitDef@ pd = (pk == 0) ? gPlant1 : gPlant2;
		gEvPlantDef[pk] = (pd is null) ? -1 : int(pd.id);
		gEvPlantV[pk] = 0.f;
		gEvPlantN[pk] = 0;
		gEvPlantUnit[pk] = -1;
		if (pd is null)
			continue;
		const int plant = int(pd.id);
		const float bp = Catalog::gBuildPower[plant];
		if (bp <= 0.f)
			continue;
		const array<int>@ prods = Catalog::gBuildsList[plant];
		for (uint q = 0; q < prods.length(); ++q) {
			const int d = prods[q];
			if (!Catalog::gAvailable[d] || !(IsBomberDef(d) || IsGunshipDef(d)) || IsAtomicDef(d))
				continue;
			const float spd = Catalog::gSpeed[d];
			if ((spd <= 0.f) || (Catalog::gSurfDps[d] <= 0.f))
				continue;
			const float obs = ObsSurv(d);
			gNaObsDmg = ObsDmg(d);
			gNaObsLost = ObsLost(d);
			for (uint i = 0; i < cs.length(); ++i) {
				const float flyS = from.distance2D(cs[i].at) / spd;
				const float fAA = NaFighterAA(cs[i].at, flyS);
				for (int nn = 1; nn <= 64; nn *= 2) {
					const float net = NaEval(cs[i], pAA[i], fAA, nn, Catalog::gHealth[d], Catalog::gSurfDps[d],
							Catalog::gCostM[d], spd, flyS, true, obs, null);
					if (net <= 0.f)
						continue;
					const float tWing = float(nn) * Catalog::gBuildTime[d] / bp;
					const float v = net / (tWing + fs);
					if (v > gEvPlantV[pk]) {
						gEvPlantV[pk] = v;
						gEvPlantN[pk] = nn;
						gEvPlantUnit[pk] = d;
					}
					break;
				}
			}
		}
	}
}

float EvPlantStrikeOf(int d)
{
	for (int pk = 0; pk < 2; ++pk) {
		if (gEvPlantDef[pk] == d)
			return gEvPlantV[pk];
	}
	return 0.f;
}

bool EvOwnMakes(bool fighter)
{
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null))
			continue;
		const array<int>@ prods = Catalog::gBuildsList[int(f.circuitDef.id)];
		for (uint q = 0; q < prods.length(); ++q) {
			if (fighter ? IsFighterDef(prods[q]) : IsLookDef(prods[q]))
				return true;
		}
	}
	return false;
}

float gEvYStrike = 0.f, gEvYFtr = 0.f, gEvYLook = 0.f;

// The production half of an air plant's price, m/s: its strike wing's net over the time to build it, less
// what a standing air plant already yields; the fighters it would make against their air while we have no
// plant that makes any; and the look, while nothing we own makes a scout.
float EvPlantProdYield(int d, float fillSec)
{
	ResolveDefs();
	const float fs = (fillSec > 1.f) ? fillSec : 180.f;
	float owned = 0.f;
	if ((gPlant1 !is null) && (Have(gPlant1) > 0))
		owned = EvPlantStrikeOf(int(gPlant1.id));
	if ((gPlant2 !is null) && (Have(gPlant2) > 0) && (EvPlantStrikeOf(int(gPlant2.id)) > owned))
		owned = EvPlantStrikeOf(int(gPlant2.id));
	float strike = EvPlantStrikeOf(d) - owned;
	if (strike < 0.f)
		strike = 0.f;
	const array<int>@ prods = Catalog::gBuildsList[d];
	float ftr = 0.f;
	float look = 0.f;
	const bool ftrOwned = EvOwnMakes(true);
	const bool lookOwned = EvOwnMakes(false);
	for (uint q = 0; q < prods.length(); ++q) {
		const int p = prods[q];
		if (!Catalog::gAvailable[p])
			continue;
		if (!ftrOwned && IsFighterDef(p)) {
			const float g = EveryFighterGainFor(p, fs);
			if (g > ftr)
				ftr = g;
		}
		if (!lookOwned && IsLookDef(p) && (look <= 0.f))
			look = LookWorth() / fs;
	}
	gEvYStrike = strike;
	gEvYFtr = ftr;
	gEvYLook = look;
	return strike + ftr + look;
}

// Where his rulings held an air plant back -- the 1v1 (2026-10-03) and the front seat of a team with a rear
// (2026-10-02) -- the reason was the army: the plant is worth the share of its army target the army holds.
float EvSeatCaution()
{
	AIFloat3 smh;
	const bool front = !IsAirLead() && !Market::gEcoRole && Military::TeamHasSheltered()
		&& (Market::ShelterMate(smh) < 0);
	if (!Duel() && !front)
		return 1.f;
	const float t = Market::ArmyTarget();
	if (t <= 1.f)
		return 1.f;
	const float f = Market::ArmyValue() / t;
	return (f > 1.f) ? 1.f : ((f < 0.f) ? 0.f : f);
}

// the conHalf's hands term for an air plant: spilled metal is metal short of hands, whatever the gap reads
float EvHandsTerm(float bpGapTerm, float pipe)
{
	const float over = Market::OverflowM() * pipe;
	return (over > bpGapTerm) ? over : bpGapTerm;
}

// The air constructor's build power per metal against the best constructor a plant we stand can make.
float EvConEff(int con)
{
	if ((con <= 0) || (Catalog::gCostM[con] <= 0.f))
		return 1.f;
	float best = 0.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null))
			continue;
		const array<int>@ prods = Catalog::gBuildsList[int(f.circuitDef.id)];
		for (uint q = 0; q < prods.length(); ++q) {
			const int p = prods[q];
			if (!Catalog::gAvailable[p] || !Catalog::gMobile[p] || !Catalog::gBuilder[p] || (Catalog::gCostM[p] <= 0.f))
				continue;
			const float r = Catalog::gBuildPower[p] / Catalog::gCostM[p];
			if (r > best)
				best = r;
		}
	}
	return (best > 0.f) ? (Catalog::gBuildPower[con] / Catalog::gCostM[con]) / best : 1.f;
}

// stat ledger
float gEvPlantVBest = 0.f, gEvAltV = 0.f;
int gEvPlantDefBest = -1, gEvOffers = 0, gEvWins = 0;
float gEvCaution = 1.f;

int gEvOfferAt = -1;

void EvNotePlant(int d, float v, float caution)
{
	++gEvOffers;
	gEvOfferAt = ai.frame;
	gEvCaution = caution;
	if (v > gEvPlantVBest) {
		gEvPlantVBest = v;
		gEvPlantDefBest = d;
	}
}

void EvNoteElection(float topV, float nextV, bool airTop)
{
	if (!EveryOn() || (gEvOfferAt != ai.frame))
		return;
	if (airTop) {
		++gEvWins;
		gEvAltV = nextV;
	} else {
		gEvAltV = topV;
	}
}

// the wing decision, per kind (0 bombers, 1 gunships)
array<string> gEvWingWhy(2, "-");
array<int> gEvGoN(2, 0);
array<int> gEvHoldN(2, 0);
int gEvGoSmall = 0;

void EvNoteWing(int kind, int chosen, bool have, float net, int n, bool extra)
{
	if ((kind < 0) || (kind > 1))
		return;
	if (chosen == NA_GO) {
		++gEvGoN[kind];
		if (extra)
			++gEvGoSmall;
		gEvWingWhy[kind] = "go(n" + n + ",net" + int(net) + (extra ? ",small" : "") + ")";
	} else {
		++gEvHoldN[kind];
		gEvWingWhy[kind] = have ? ("hold(n" + n + ",net" + int(net) + ")") : ("hold(n" + n + ",nocell)");
	}
}

void EvNoteSkip(int kind, const string &in why)
{
	if ((kind >= 0) && (kind <= 1))
		gEvWingWhy[kind] = why;
}

int gEvStatAt = 0;

void EveryStat()
{
	if (ai.frame < gEvStatAt)
		return;
	gEvStatAt = ai.frame + 60 * SECOND;
	ResolveDefs();
	ai.PublishTeamValue("airplants", float(Have(gPlant1) + Have(gPlant2)));
	int seats = 0, mates = 0;
	if (gMatesCache is null)
		@gMatesCache = ai.GetTeamIds();
	array<Id>@ ms = gMatesCache;
	if (ms !is null) {
		for (uint i = 0; i < ms.length(); ++i) {
			++mates;
			if (ai.ReadTeamValue(int(ms[i]), "airplants", 0.f) > 0.5f)
				++seats;
		}
	}
	int bombers = 0, fighters = 0, gunships = 0, scouts = 0, cons = 0, idle = 0;
	float ftrM = 0.f;
	const array<int>@ own = Market::OwnedDefs();
	for (uint oi = 0; oi < own.length(); ++oi) {
		const int d = own[oi];
		if (!Catalog::gFlyer[d] || !Catalog::gMobile[d])
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(d), Builder::gHomePos, 0.f);
		const int n = (us is null) ? 0 : int(us.length());
		if (n == 0)
			continue;
		if (Catalog::gBuilder[d]) {
			cons += n;
			continue;
		}
		if (IsBomberDef(d))
			bombers += n;
		else if (IsFighterDef(d)) {
			fighters += n;
			ftrM += float(n) * Catalog::gCostM[d];
		} else if (IsGunshipDef(d))
			gunships += n;
		else if (Catalog::gPower[d] <= 1.f)
			scouts += n;
		if (Catalog::gPower[d] <= 1.f)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] !is null) && (us[k].CmdQueueSize() == 0))
				++idle;
		}
	}
	int ftrPend = 0;
	for (int pass = 0; pass < 2; ++pass) {
		CCircuitDef@ fd = (pass == 0) ? gFighter : gFighter1;
		if (fd !is null)
			ftrPend += Brain::PendAnyOf(int(fd.id));
	}
	EvSnapFoeAir();
	float ftrWant = 0.f;
	CCircuitDef@ wf = (gFighter !is null && Have(gPlant2) > 0) ? gFighter : gFighter1;
	if (wf !is null)
		ftrWant = EvFighterWantM(int(wf.id)) * EvFighterShare();
	LifeStat();
	AiLog(Factory::T() + "apex: airevery-stat t=" + ai.teamId + " on=" + (EveryOn() ? 1 : 0)
		+ " seats=" + seats + "/" + mates
		+ " plants=" + Have(gPlant1) + "," + Have(gPlant2)
		+ " plantV=" + Market::NnF(gEvPlantVBest * 1000.f, 2)
		+ ((gEvPlantDefBest > 0) ? (":" + Catalog::Def(gEvPlantDefBest).GetName()) : "")
		+ " altV=" + Market::NnF(gEvAltV * 1000.f, 2)
		+ " offers=" + gEvOffers + " wins=" + gEvWins
		+ " y=[strike " + Market::NnF(gEvYStrike, 2) + " ftr " + Market::NnF(gEvYFtr, 2)
		+ " look " + Market::NnF(gEvYLook, 2) + " caution " + Market::NnF(gEvCaution, 2) + "]"
		+ " air=[bomb " + bombers + " ftr " + fighters + " gun " + gunships + " scout " + scouts + " con " + cons + "]"
		+ " idle=" + idle
		+ " wing=[b " + gEvWingWhy[0] + " g " + gEvWingWhy[1] + "]"
		+ " go=" + gEvGoN[0] + "/" + gEvGoN[1] + " hold=" + gEvHoldN[0] + "/" + gEvHoldN[1] + " small=" + gEvGoSmall
		+ " foeAir=" + int(gEvFoeAirM) + "(ftr " + int(gEvFoeFtrM) + " strike " + int(gEvFoeStrM) + ")"
		+ " ourFtrM=" + int(ftrM) + " ftrWant=" + int(ftrWant) + " ftrPend=" + ftrPend
		+ " hunt=" + gEvHuntLaunch + "/" + gEvHuntN + "/" + gEvHuntHold + ":" + gEvHuntWhy);
	gEvPlantVBest = 0.f;
	gEvPlantDefBest = -1;
	gEvOffers = 0;
	gEvWins = 0;
}

}  // namespace Air
