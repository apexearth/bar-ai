namespace Market {

// One `apex: nn` line per EXECUTED builder decision: the state, the ranked
// options as priced, which one ran, and each option's chance of being drawn.
// tools/decisions.py joins it to the infolog outcomes. Rides apex_decide_log.
// NnScore is the same net played back: tools/nntrain.py trains it on these
// lines and writes nnweights.as, whose inputs must be built exactly as here.

const uint NN_K = 8;
const string NN_STATE = "min,mInc,eInc,mCur,mStor,eCur,eStor,mPull,ePull,eSur,eExcess,ecoP,slack,"
	+ "eStall,eFeed,ePinned,mStarved,mWasting,hands,idleNanoM,openSpots,upDemand,backlogM,tier,"
	+ "army,teamArmy,foeArmy,foeMass,stance,losing,contested,outmassed,trade,tradeOk,lossPress,"
	+ "mex,staticLoss,airLoss,mobileLoss,structBleed,airNow,airSeen,incoming,raidP,sinceRaid,"
	+ "intelFresh,foeSilos,comm,homeD,allies,foeTeam,mapArea,"
	+ "plantM,nanoBP,convCap,defM,antiN,stockN,"
	+ "shArmy,shDef,shAirdef,shEco,shBP,tgArmy,tgDef,tgAirdef,tgEco,tgBP,"
	+ "foeT2,foeHeavy,foeArty,foeRaider,foeStatic,ourQual,foeQual,"
	+ "dgA60,dgA120,dgA180,homeStr,home60,dgRatio,dgGap,foeEta,foeBaseD,"
	+ "foeLiveM,foeRemM,foeLostM,foeRemEta,foeCert,"
	+ "wreckHome,wreckArmy,wreckRate,rezN,repairM,"
	+ "foeLrpc,plasma,ownLrpc,ownShield,conShare,ourBonus,foeBonus";
const string NN_OPT = "cat,kind,def,value,gain,m,t,cm,ce,bt,walk,risk,eta,dPow,ownN,tierO,fwd,"
	+ "siteLoss,persona,x,z,p,nm,forced";
// value..persona: the net's per-option numbers, in NnOpt order
const uint NN_ONUM = 16;
const float NN_ETA_CAP = 3600.f;

// What we own, read off the commitment ledger in metal and capacity rather
// than counts, so "a T2 lab" needs no cost threshold.
array<float> gNnHold(6);
int gNnHoldStamp = -1;
int gNnHoldAt = -1000;

// One rule, the same as tools/imitate.py classify() on the catalog dump, so the
// BARb prior means the same thing offline and here. -1 = not a structure.
const int NC_MEX = 0, NC_ENERGY = 1, NC_CONVERT = 2, NC_STORE = 3, NC_PLANT = 4,
	NC_NANO = 5, NC_PROTECT = 6, NC_AIRDEF = 7, NC_OTHER = 8, NC_N = 9;
array<float> gNnClassN(NC_N);   // our finished structures by class (NnHoldings)

int NnClassOf(int d)
{
	if ((d < 0) || (d >= int(Catalog::gCostM.length())) || Catalog::gMobile[d])
		return -1;
	const array<int>@ bo = Catalog::BuildsOf(d);
	if ((bo !is null) && (bo.length() > 0))
		return NC_PLANT;
	if (Catalog::gBuildPower[d] > 0.f)
		return NC_NANO;
	if (Catalog::gExtractsM[d] > 0.f)
		return NC_MEX;
	if (Catalog::gConvCapacity[d] > 0.f)
		return NC_CONVERT;
	if ((Catalog::gMakeE[d] > 0.f) || Catalog::gWind[d])
		return NC_ENERGY;
	if ((Catalog::gMaxRange[d] > 0.f) && (Catalog::gAirT[d] > 0.f) && (Catalog::gSurfT[d] <= 0.f))
		return NC_AIRDEF;
	if (Catalog::gMaxRange[d] > 0.f)
		return NC_PROTECT;
	if ((Catalog::gStoreM[d] > 0.f) || (Catalog::gStoreE[d] > 0.f))
		return NC_STORE;
	return NC_OTHER;
}

void NnHoldings()
{
	if ((gNnHoldStamp == gComStamp) && (ai.frame - gNnHoldAt < 30))
		return;
	gNnHoldStamp = gComStamp;
	gNnHoldAt = ai.frame;
	for (uint k = 0; k < gNnHold.length(); ++k)
		gNnHold[k] = 0.f;
	for (uint k = 0; k < gNnClassN.length(); ++k)
		gNnClassN[k] = 0.f;
	for (uint i = 0; i < ComLen(); ++i) {
		const int d = gComDef[i];
		if ((d < 0) || (d >= int(Catalog::gCostM.length())) || ((gComState[i] & CS_COMING) != 0))
			continue;
		const int nc = NnClassOf(d);
		if (nc >= 0)
			gNnClassN[nc] += 1.f;
		const float cm = Catalog::gCostM[d];
		// nano turrets are not IsBuilder(): build power with no build list is the
		// census's own test (census.as)
		const array<int>@ bo = Catalog::BuildsOf(d);
		if ((bo !is null) && (bo.length() > 0))
			gNnHold[0] += cm;
		else if (Catalog::gBuildPower[d] > 0.f)
			gNnHold[1] += Catalog::gBuildPower[d];
		else if (Catalog::gAntiNuke[d])
			gNnHold[4] += 1.f;
		else if (Catalog::gStock[d])
			gNnHold[5] += 1.f;
		else if (Catalog::gMaxRange[d] > 0.f)
			gNnHold[3] += cm;
		gNnHold[2] += Catalog::gConvCapacity[d];
	}
}

// Share of the enemy army cost we know that was seen recently: 1 = the
// foeArmy reading is current, 0 = it is all ghosts (or we are blind).
float NnIntelFresh()
{
	const array<int> roles = {Unit::Role::ASSAULT.type, Unit::Role::RAIDER.type,
		Unit::Role::RIOT.type, Unit::Role::SKIRM.type, Unit::Role::ARTY.type, Unit::Role::AH.type};
	float raw = 0.f, fresh = 0.f;
	for (uint i = 0; i < roles.length(); ++i) {
		const float r = aiEnemyMgr.GetEnemyCost(roles[i]);
		const float f = aiEnemyMgr.GetEnemyCostFresh(roles[i]);
		raw += r;
		fresh += (f < r) ? f : r;
	}
	return (raw > 0.f) ? fresh / raw : 0.f;
}

array<float> gNnP(CAT_N + 1);
array<Want@> gNnBest(CAT_N + 1);
int gNnDrawAt = -1;
int gNnDrawUnit = -1;
string gNnDrawMode = "";
bool gNnHeader = false;
array<Want@> gNnSnap;
int gNnSnapAt = -1;
int gNnSnapUnit = -1;
uint gNnLines = 0;

void NnNoteDraw(CCircuitUnit@ unit, array<Want@>@ ranked, const array<int>& in catBest,
		const array<float>& in wt, float sum, const string& in mode)
{
	gNnDrawAt = ai.frame;
	gNnDrawUnit = int(unit.id);
	gNnDrawMode = mode;
	for (int c = 0; c <= CAT_N; ++c) {
		gNnP[c] = (sum > 0.f) ? (wt[c] / sum) : 0.f;
		@gNnBest[c] = (catBest[c] >= 0) ? ranked[uint(catBest[c])] : null;
		if (gNnBest[c] !is null)
			gNnBest[c].nnDrawP = gNnP[c];
	}
}

void NnSnapshot(CCircuitUnit@ unit, array<Want@>@ ranked)
{
	gNnSnapAt = ai.frame;
	gNnSnapUnit = int(unit.id);
	const uint n = (ranked.length() < NN_K) ? ranked.length() : NN_K;
	gNnSnap.resize(n);
	for (uint i = 0; i < n; ++i)
		@gNnSnap[i] = ranked[i];
}

string NnF(float x, int d)
{
	return formatFloat(x, "", 0, d);
}

float NnB(bool b)
{
	return b ? 1.f : 0.f;
}

// Only comm and homeD depend on the asker; the rest is computed once a frame.
const uint NN_I_COMM = 47;
const uint NN_I_HOMED = 48;
array<float> gNnSt;
int gNnStAt = -1;

// In NN_STATE order. A null unit is a team-level decision (a bomber strike):
// it stands at home.
// Wreck metal in sight within half the way to their base: what lies in front
// of ours. On a 5 s clock -- a feature-field query.
float gNnWreckHome = 0.f;
int gNnWreckAt = -1000;
float NnWreckHome()
{
	if (ai.frame - gNnWreckAt < 5 * SECOND)
		return gNnWreckHome;
	gNnWreckAt = ai.frame;
	const float r = 0.5f * Military::FoeBaseDist();
	gNnWreckHome = (Builder::gHomeSet && (r > 0.f)) ? ai.GetWreckValueAt(Builder::gHomePos, r) : 0.f;
	return gNnWreckHome;
}

float gNnOurBonus = 0.f, gNnFoeBonus = 0.f;
int gNnBonusAt = -1000000;
void NnBonusRefresh()
{
	if (ai.frame - gNnBonusAt < 30 * SECOND)
		return;
	const bool first = gNnBonusAt < 0;
	gNnBonusAt = ai.frame;
	gNnOurBonus = ai.GetTeamIncomeMult(ai.teamId) - 1.f;
	const float foe = ai.GetFoeIncomeMultMax();
	gNnFoeBonus = (foe > 0.f) ? (foe - 1.f) : 0.f;
	if (first)
		AiLog("apex: nn-bonus t=" + ai.teamId + " ours=" + gNnOurBonus + " foe=" + gNnFoeBonus);
}

void NnState(CCircuitUnit@ unit, array<float>& out s)
{
	const AIFloat3 up = (unit !is null) ? unit.GetPos(ai.frame)
			: (Builder::gHomeSet ? Builder::gHomePos : AIFloat3());
	if (gNnStAt != ai.frame) {
		NnStateFull(up, gNnSt);
		gNnStAt = ai.frame;
	}
	s = gNnSt;
	s[NN_I_COMM] = NnB((unit !is null) && unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask));
	s[NN_I_HOMED] = Builder::gHomeSet ? up.distance2D(Builder::gHomePos) : -1.f;
}

void NnStateFull(const AIFloat3& in up, array<float>& out s)
{
	NnHoldings();
	s.resize(0);
	s.insertLast(float(ai.frame) / 1800.f);
	s.insertLast(Eco::MInc());
	s.insertLast(Eco::EInc());
	s.insertLast(Eco::MCur());
	s.insertLast(Eco::MStor());
	s.insertLast(Eco::ECur());
	s.insertLast(Eco::EStor());
	s.insertLast(Eco::MPull());
	s.insertLast(Eco::EPull());
	s.insertLast(gESurplusEma);
	s.insertLast(gEExcessEma);
	s.insertLast(EcoPowerM());
	s.insertLast(SlackFrac());
	s.insertLast(NnB(HardEStall()));
	s.insertLast(EFeedShare());
	s.insertLast(NnB(EnergyPinned()));
	s.insertLast(NnB(MetalPathStarved()));
	s.insertLast(NnB(MetalWasting()));
	s.insertLast(EtaHandsShare());
	s.insertLast(IdleNanoLatheM());
	s.insertLast(float(ClaimableSpots()));
	s.insertLast(DisplacedStreamM());
	s.insertLast(BacklogM());
	s.insertLast(float(TopOwnPlantTier()));
	s.insertLast(Military::OurArmyNow());
	s.insertLast(Military::TeamArmyCost());
	s.insertLast(Military::EnemyArmyCost());
	s.insertLast(Military::EnemyMassingThreat());
	s.insertLast(float(Military::Stance()));
	s.insertLast(NnB(Military::LosingGround()));
	s.insertLast(NnB(Military::BaseContested()));
	s.insertLast(NnB(Military::Outmassed()));
	s.insertLast(Military::TradeRatio());
	s.insertLast(NnB(Military::TradeMeaningful()));
	s.insertLast(Military::LossPressureFrac());
	s.insertLast(float(OwnMexCount()));
	s.insertLast(Military::StaticLossRate());
	s.insertLast(Military::AirLossRate());
	s.insertLast(Military::gDeadToMobile / Military::BLEED_TAU);
	s.insertLast(BleedM());
	s.insertLast(Military::AirThreatNow());
	s.insertLast(Military::AirSeenEver());
	s.insertLast(Military::IncomingCost());
	s.insertLast(Military::RaidPressure());
	const float since = float(ai.frame - Military::gRaidAt) / 30.f;
	s.insertLast((since > NN_ETA_CAP) ? NN_ETA_CAP : since);
	s.insertLast(NnIntelFresh());
	s.insertLast(float(Brain::EnemyNukeSilos()));
	s.insertLast(0.f);   // comm, set per asker
	s.insertLast(0.f);   // homeD, set per asker
	s.insertLast(float(Military::AllyCount()));
	s.insertLast(float(ai.GetEnemyTeamSize()));
	s.insertLast(float(AiTerrainWidth()) * float(AiTerrainHeight()));
	for (uint k = 0; k < gNnHold.length(); ++k)
		s.insertLast(gNnHold[k]);
	s.insertLast(Brain::ShareOf(Brain::ARMY));
	s.insertLast(Brain::ShareOf(Brain::DEFENCE));
	s.insertLast(Brain::ShareOf(Brain::AIRDEF));
	s.insertLast(Brain::ShareOf(Brain::ECONOMY));
	s.insertLast(Brain::ShareOf(Brain::BUILDPOWER));
	s.insertLast(Brain::TargetShare(Brain::ARMY));
	s.insertLast(Brain::TargetShare(Brain::DEFENCE));
	s.insertLast(Brain::TargetShare(Brain::AIRDEF));
	s.insertLast(Brain::TargetShare(Brain::ECONOMY));
	s.insertLast(Brain::TargetShare(Brain::BUILDPOWER));
	// what the enemy fields: its share above T1, its heavy/arty/raider/static
	// metal, and strength per metal of our units against theirs
	s.insertLast(Military::FoeTierAbove(1));
	s.insertLast(Military::EnemyCostOf(Unit::Role::HEAVY.type));
	s.insertLast(Military::EnemyCostOf(Unit::Role::ARTY.type));
	s.insertLast(Military::EnemyCostOf(Unit::Role::RAIDER.type));
	s.insertLast(Military::EnemyCostOf(Unit::Role::STATIC.type));
	s.insertLast(OurQualityM());
	s.insertLast(FoeQualityM());
	// danger: enemy strength that can reach our base edge within 1/2/3 min, vs ours there
	s.insertLast(Military::DangerArriveS(60.f));
	s.insertLast(Military::DangerArriveS(120.f));
	s.insertLast(Military::DangerArriveS(180.f));
	s.insertLast(Military::HomeStrength());
	s.insertLast(Military::HomeStrengthS(60.f));
	s.insertLast(Military::DangerRatio(60.f));
	s.insertLast(Military::DangerGap());
	s.insertLast(Military::NearestFoeEtaS());
	s.insertLast(Military::FoeBaseDist());
	// their army as remembered: in sight, out of sight where we think it is, lost track of
	s.insertLast(Military::FoeLiveM());
	s.insertLast(Military::FoeRememberedM());
	s.insertLast(Military::FoeLostM());
	s.insertLast(Military::FoeRememberedEtaS());
	s.insertLast(Military::FoeMemCertainty());
	// reclaim: wreck metal we can see on our half of the map and where the army
	// stands, how fast new wrecks appear, our rez bots, our repair backlog
	s.insertLast(NnWreckHome());
	s.insertLast(Builder::WreckSeenValue());
	s.insertLast(Military::WreckRateM());
	s.insertLast(float(Builder::RezCount()));
	s.insertLast(ai.GetOwnRepairM());
	// the late game: their long-range cannons, what they shell us for, our answers
	s.insertLast(float((EnemyLRPCs() > 0) ? EnemyLRPCs() : ((Military::PlasmaLossRate() > 0.f) ? 1 : 0)));
	s.insertLast(Military::PlasmaLossRate());
	s.insertLast(float(SuperHave(SC_LRPC)));
	s.insertLast(float(gProtIds[PROT_SHIELD].length()));
	s.insertLast(ConShare());
	// the lobby bonuses: a +65 game's habits must not read as a +0 game's
	NnBonusRefresh();
	s.insertLast(gNnOurBonus);
	s.insertLast(gNnFoeBonus);
}

// The market's own numbers for one option, every multiplier the net or the
// discovery dice applied taken back out (nnMult), so the net never learns from
// its own opinion.
void NnOpt(Want@ w, const AIFloat3& in up, array<float>& out o)
{
	if (w.nnOpt !is null) {
		o = w.nnOpt;
		return;
	}
	NnOptFull(w, up, o);
	@w.nnOpt = array<float>();
	w.nnOpt = o;
}

void NnOptFull(Want@ w, const AIFloat3& in up, array<float>& out o)
{
	const int di =((w.def is null) || (int(w.def.id) >= int(Catalog::gCostM.length())))
			? -1 : int(w.def.id);
	const bool on = OnMap(w.pos);
	o.resize(NN_ONUM);
	o[0] = w.value * 1000.f / w.nnMult;
	o[1] = w.gain;
	o[2] = w.mCost;
	o[3] = w.tCost;
	o[4] = (di >= 0) ? Catalog::gCostM[di] : 0.f;
	o[5] = (di >= 0) ? Catalog::gCostE[di] : 0.f;
	o[6] = (di >= 0) ? Catalog::gBuildTime[di] : 0.f;
	o[7] = on ? w.pos.distance2D(up) : -1.f;
	o[8] = on ? ExpectedLossAt(w.pos, w.mCost) : 0.f;
	float eta = NN_ETA_CAP;
	if ((di >= 0) && EtaOn() && EtaRanks(w)) {
		const float e = EtaOfWant(w);
		eta = (e < NN_ETA_CAP) ? e : NN_ETA_CAP;
	}
	o[9] = eta;
	o[10] = (di >= 0) ? DPowerOf(w, di) : 0.f;
	o[11] = ((di >= 0) && (di < int(gOwnCount.length()))) ? float(gOwnCount[di]) : 0.f;
	o[12] = (di >= 0) ? float(DefTier(di)) : 0.f;
	o[13] = on ? Military::ForwardFraction(w.pos) : 0.f;
	o[14] = on ? LossRateAt(w.pos) : 0.f;
	const int cat = CategoryOf(w.kind);
	o[15] = ((w.kind != WK_SUPER) && (cat >= 0)) ? Persona::CategoryMult(cat) : 1.f;
}

// DISCOVERY GAMES: in apex_nn_explore of games the explorer's team plays ONE
// whole strategy drawn from the plan net's options (plannet.as) and every
// other head plays its rule or net as in any game, so the outcome belongs to
// the strategy (docs/35).
bool gNnExploreRolled = false;
bool gNnExplore = false;
bool gNnExploreSaid = false;
// A head whose net has no trust plays its rule at p=1 and would never see an
// alternative: in a discovery game it alone mixes this much uniform in.
const float NN_HEAD_FLAT = 0.1f;

void NnExploreRoll()
{
	if (gNnExploreRolled)
		return;
	gNnExploreRolled = true;
	const float chance = ai.GetTunable("apex_nn_explore", TUNE_NN_EXPLORE);
	const int explorer = int(ai.GetTunable("apex_nn_explore_team", TUNE_NN_EXPLORE_TEAM));
	gNnExplore = (explorer >= 0) ? (explorer == ai.teamId)
			: (float(AiRandom(0, 10000)) / 10000.f < chance);
	if (gNnExplore)
		AiLog("apex: nn-explore t=" + ai.teamId + " on | headFlat=" + NnF(NN_HEAD_FLAT, 2));
}

// A standard normal draw (Irwin-Hall); the explorer's once-per-game plant-type lean uses it.
float NnGauss()
{
	float s = 0.f;
	for (int i = 0; i < 12; ++i)
		s += float(AiRandom(0, 10000)) / 10000.f;
	return s - 6.f;
}

float NnHeadFlat(float trust)
{
	return (gNnExploreRolled && gNnExplore && (trust <= 0.f)) ? NN_HEAD_FLAT : 0.f;
}

// Said once, when the explorer first knows its strategy, so a watcher knows
// which side is different and what it tries.
void NnExploreSay(const string& in plan, const string& in how)
{
	if (gNnExploreSaid || !gNnExplore)
		return;
	gNnExploreSaid = true;
	ai.SendChat("Team " + ai.teamId + " is the DISCOVERY explorer this game: strategy " + plan + " (" + how + ")");
	ai.DrawPoint(aiSetupMgr.GetBasePos(), "Discovery explorer: team " + ai.teamId + " " + plan);
}

void NnRecord(CCircuitUnit@ unit, Want@ chosen, uint depth, const string& in why)
{
	if ((gNnSnapAt != ai.frame) || (gNnSnapUnit != int(unit.id)))
		return;
	const double _t = Perf::T0();
	NnExploreRoll();
	if (!gNnHeader) {
		gNnHeader = true;
		AiLog("apex: nn-schema v10 state=" + NN_STATE + " opt=" + NN_OPT + " k=" + NN_K
			+ " net=" + (NNW_ON ? NNW_GAMES : -1) + " explore=" + (gNnExplore ? 1 : 0) + " comb=trust");
	}
	const bool here = (gNnDrawAt == ai.frame) && (gNnDrawUnit == int(unit.id));
	// A ladder hoist or a kept tech lab is not sampled: the top option ran with p=1.
	const bool drew = here && (gNnDrawMode == "draw");
	const AIFloat3 up = unit.GetPos(ai.frame);
	string ln = "apex: nn t=" + ai.teamId + " f=" + ai.frame + " u=" + unit.id
		+ " c=" + unit.circuitDef.GetName() + " pick=" + depth
		+ " why=" + why + " dm=" + (here ? gNnDrawMode : "none") + " |";
	array<float> s;
	NnState(unit, s);
	for (uint k = 0; k < s.length(); ++k)
		ln += ((k == 0) ? " " : ",") + NnF(s[k], 2);
	int ci = -1;
	array<float> o;
	for (uint i = 0; i < gNnSnap.length(); ++i) {
		Want@ w = gNnSnap[i];
		if (w is chosen)
			ci = int(i);
		const int cat = CategoryOf(w.kind);
		float p = 0.f;
		if (!drew)
			p = (i == 0) ? 1.f : 0.f;
		else if ((cat >= 0) && (gNnBest[cat] is w))
			p = gNnP[cat];
		// another hand's draw since overwrote the globals: the odds rode on the want
		if (!here && (why == "draw") && (w.nnDrawP >= 0.f))
			p = w.nnDrawP;
		NnOpt(w, up, o);
		ln += (i == 0 ? " | " : " ; ") + CatName(cat) + "," + KindName(w.kind)
			+ "," + ((w.def is null) ? "-" : w.def.GetName());
		for (uint k = 0; k < NN_ONUM; ++k)
			ln += "," + NnF(o[k], (k < 2) ? 3 : 2);
		ln += "," + int(w.pos.x) + "," + int(w.pos.z) + "," + NnF(p, 6) + "," + NnF(w.nnMult, 3)
			+ "," + (w.nnPriced ? 0 : 1);
	}
	ln += " | chosen=" + ci;
	AiLog(ln);
	++gNnLines;
	Perf::Add("dec.nnrec", _t);
}

string NnStateText(CCircuitUnit@ unit)
{
	array<float> s;
	NnState(unit, s);
	string t = "";
	for (uint k = 0; k < s.length(); ++k)
		t += ((k == 0) ? "" : ",") + NnF(s[k], 2);
	return t;
}

// FACTORY PRODUCTION, the second decision type: one `apex: nnfac` line per
// order, every candidate with its draw chance (value / sum -- the roulette's
// own odds), so production can be learned exactly like the builder record.
bool gNnFacHeader = false;

float NnSlog(float x)
{
	const float a = log(1.f + abs(x));
	return (x < 0.f) ? -a : a;
}

// A candidate unit described by what it IS, so the net generalises across defs:
// value,gain,cm,ce,bt,tierO,ownN,hp,speed,range,power,fly,bld,rez,bp,radarR (NNF_ONUM).
const uint NNF_ONUM = 16;
const uint NNF_K = 24;

void NnFacOpt(int d, float value1000, float gain, array<float>& out o)
{
	o.resize(NNF_ONUM);
	o[0] = value1000;
	o[1] = gain;
	o[2] = Catalog::gCostM[d];
	o[3] = Catalog::gCostE[d];
	o[4] = Catalog::gBuildTime[d];
	o[5] = float(DefTier(d));
	o[6] = (d < int(gOwnCount.length())) ? float(gOwnCount[d]) : 0.f;
	o[7] = Catalog::gHealth[d];
	o[8] = Catalog::gSpeed[d];
	o[9] = Catalog::gMaxRange[d];
	o[10] = Catalog::gPower[d];
	o[11] = Catalog::gFlyer[d] ? 1.f : 0.f;
	o[12] = Catalog::gBuilder[d] ? 1.f : 0.f;
	// a rez bot is not a constructor: what it is for is the wreck field
	o[13] = Catalog::gRezzer[d] ? 1.f : 0.f;
	o[14] = Catalog::gBuildPower[d];
	o[15] = Catalog::gRadar[d] ? Catalog::gRadarR[d] : 0.f;
}

bool NnFacWeightsFit()
{
	const int N = NNF_S + NNF_O;
	return NNF_ON && (NNF_STATE == NN_STATE) && (NNF_S > 0) && (NNF_H > 0)
		&& (NNF_O == int(NNF_ONUM) + 2)
		&& (NNF_XM.length() == uint(N)) && (NNF_XS.length() == uint(N))
		&& (NNF_W1.length() == uint(NNF_H * N)) && (NNF_B1.length() == uint(NNF_H))
		&& (NNF_W2.length() == uint(NNF_H * NNF_H)) && (NNF_B2.length() == uint(NNF_H))
		&& (NNF_WO.length() == uint(NNF_H));
}

// THE FACTORY NET: scores every candidate of a production order and moves its
// roulette weight in log space by the trust the factory net has earned, as the
// builder net does. Returns the new weight sum; mult[] carries each move so the
// record can divide it back out.
uint gNnFacScored = 0;
uint gNnFacChanged = 0;
int gNnFacLogAt = 0;

float NnFacScore(CCircuitUnit@ fac, const array<int>& in defs, array<float>& vals,
		const array<float>& in gains, array<float>& out mult)
{
	mult.resize(defs.length());
	float sum = 0.f;
	for (uint i = 0; i < defs.length(); ++i) {
		mult[i] = 1.f;
		sum += vals[i];
	}
	const float blend = ai.GetTunable("apex_nn_blend", TUNE_NN_BLEND);
	const float t = (blend * NNF_TRUST > 1.f) ? 1.f : blend * NNF_TRUST;
	if ((t <= 0.f) || (defs.length() < 2) || !NnFacWeightsFit())
		return sum;
	const double _t = Perf::T0();
	const int S = NNF_S, O = NNF_O, H = NNF_H, N = NNF_S + NNF_O;
	array<float> s;
	NnState(fac, s);
	array<float> a(H);
	for (int h = 0; h < H; ++h)
		a[h] = NNF_B1[h];
	for (int i = 0; i < S; ++i) {
		float z = (NnSlog(s[i]) - NNF_XM[i]) / NNF_XS[i];
		z = (z > 6.f) ? 6.f : ((z < -6.f) ? -6.f : z);
		for (int h = 0; h < H; ++h)
			a[h] += NNF_W1[h * N + i] * z;
	}
	const uint n = (defs.length() < NNF_K) ? defs.length() : NNF_K;
	float best = -1e30f;
	for (uint r = 0; r < n; ++r)
		best = (vals[r] * 1000.f > best) ? vals[r] * 1000.f : best;
	array<float> score(n), x(O), h1(H), o;
	float mean = 0.f, meanLv = 0.f;
	uint nLv = 0, top0 = 0;
	for (uint r = 0; r < n; ++r) {
		top0 = (vals[r] > vals[top0]) ? r : top0;
		NnFacOpt(defs[r], vals[r] * 1000.f, gains[r], o);
		for (uint k = 0; k < NNF_ONUM; ++k)
			x[k] = NnSlog(o[k]);
		x[NNF_ONUM] = NnSlog(o[0] - best);
		x[NNF_ONUM + 1] = NnSlog(float(n));
		for (int h = 0; h < H; ++h)
			h1[h] = a[h];
		for (int i = 0; i < O; ++i) {
			float z = (x[i] - NNF_XM[S + i]) / NNF_XS[S + i];
			z = (z > 6.f) ? 6.f : ((z < -6.f) ? -6.f : z);
			for (int h = 0; h < H; ++h)
				h1[h] += NNF_W1[h * N + S + i] * z;
		}
		float sc = NNF_BO;
		for (int h2 = 0; h2 < H; ++h2) {
			float acc = NNF_B2[h2];
			for (int h = 0; h < H; ++h) {
				if (h1[h] > 0.f)
					acc += NNF_W2[h2 * H + h] * h1[h];
			}
			if (acc > 0.f)
				sc += NNF_WO[h2] * acc;
		}
		score[r] = sc;
		mean += sc;
		if (vals[r] > 0.f) {
			meanLv += log(vals[r]);
			++nLv;
		}
	}
	mean /= float(n);
	meanLv = (nLv > 0) ? meanLv / float(nLv) : 0.f;
	sum = 0.f;
	uint top1 = 0;
	for (uint r = 0; r < defs.length(); ++r) {
		if ((r < n) && (vals[r] > 0.f)) {
			float d = score[r] - mean;
			d = (d > 3.f) ? 3.f : ((d < -3.f) ? -3.f : d);
			const float lv = log(vals[r]);
			mult[r] = pow(2.7182818f, (1.f - t) * (lv - meanLv) + t * d - (lv - meanLv));
			vals[r] *= mult[r];
		}
		sum += vals[r];
		top1 = (vals[r] > vals[top1]) ? r : top1;
	}
	++gNnFacScored;
	if (top1 != top0)
		++gNnFacChanged;
	if (ai.frame >= gNnFacLogAt) {
		gNnFacLogAt = ai.frame + 60 * SECOND;
		AiLog("apex: nnfac-score t=" + ai.teamId + " trust=" + NnF(t, 2) + " scored=" + gNnFacScored
			+ " topChanged=" + gNnFacChanged);
	}
	Perf::Add("fac.nn", _t);
	return sum;
}

void NnFacRecord(CCircuitUnit@ fac, const array<int>& in defs, const array<float>& in vals,
		const array<float>& in gains, float sum, uint pick, const array<float>& in mult)
{
	const double _t = Perf::T0();
	if (!gNnFacHeader) {
		gNnFacHeader = true;
		AiLog("apex: nnfac-schema v3 state=" + NN_STATE
			+ " opt=def,value,gain,cm,ce,bt,tierO,ownN,hp,speed,range,power,fly,bld,rez,bp,radarR,p,nm");
	}
	string ln = "apex: nnfac t=" + ai.teamId + " f=" + ai.frame + " u=" + fac.id
		+ " c=" + fac.circuitDef.GetName() + " | " + NnStateText(fac) + " |";
	const uint n = (defs.length() < NNF_K) ? defs.length() : NNF_K;
	array<float> o;
	for (uint i = 0; i < n; ++i) {
		const float m = ((i < mult.length()) && (mult[i] > 0.f)) ? mult[i] : 1.f;
		NnFacOpt(defs[i], vals[i] * 1000.f / m, gains[i], o);
		ln += ((i == 0) ? " " : " ; ") + Catalog::Def(defs[i]).GetName();
		for (uint k = 0; k < NNF_ONUM; ++k)
			ln += "," + NnF(o[k], (k < 2) ? 3 : 1);
		ln += "," + NnF((sum > 0.f) ? vals[i] / sum : 0.f, 6) + "," + NnF(m, 3);
	}
	ln += " | chosen=" + ((pick < n) ? int(pick) : -1);
	AiLog(ln);
	Perf::Add("fac.nnrec", _t);
}

// THE NET AS A MODIFIER: it scores the top options and multiplies their market
// value by exp(blend * how much better than the others it expects each to do).
// The market still proposes every option; the net only reweights the draw.
uint gNnScored = 0;
uint gNnTopChanged = 0;
int gNnLogAt = 0;
bool gNnBad = false;
array<float> gNnA;
array<float> gNnX;
array<float> gNnH1;

// KindName(k)'s slot in NNW_KINDS, built once: no string compares per option.
array<int> gNnKindSlot;

bool NnWeightsFit()
{
	const int N = NNW_S + NNW_O;
	return (NNW_STATE == NN_STATE) && (NNW_S > 0) && (NNW_H > 0)
		&& (NNW_O == int(NNW_KINDS.length() + NN_ONUM) + 4)
		&& (NNW_XM.length() == uint(N)) && (NNW_XS.length() == uint(N))
		&& (NNW_W1.length() == uint(NNW_H * N)) && (NNW_B1.length() == uint(NNW_H))
		&& (NNW_W2.length() == uint(NNW_H * NNW_H)) && (NNW_B2.length() == uint(NNW_H))
		&& (NNW_WO.length() == uint(NNW_H))
		&& (NNW_TRUST.length() == NNW_KINDS.length());
}

array<string> gNnOffSaid;

// A decision head's net (NNC_ commander, NNT_ T2; the posture net has its own
// copy): scores each option from the state, the head's own fields, the option
// and the rule's pick, and moves the option weights in log space by the trust
// it has earned. Returns that trust (0 = the rule alone).
float NnHeadScore(bool on, const string& in layout, const string& in own, int S, int O, int H,
	const array<float>& in XM, const array<float>& in XS, const array<float>& in W1,
	const array<float>& in B1, const array<float>& in W2, const array<float>& in B2,
	const array<float>& in WO, float BO, float trust0,
	const array<float>& in st, const array<float>& in f, array<float>& w)
{
	const int K = int(w.length()), N = S + O;
	float t = ai.GetTunable("apex_nn_blend", TUNE_NN_BLEND) * trust0;
	t = (t > 1.f) ? 1.f : t;
	if ((t <= 0.f) || !on)
		return 0.f;
	if ((layout != NN_STATE + "|" + own) || (O != 2 * K)
		|| (S != int(st.length() + f.length())) || (H <= 0) || (XM.length() != uint(N))
		|| (W1.length() != uint(H * N)) || (W2.length() != uint(H * H)) || (WO.length() != uint(H)))
	{
		// a trusted net refused for its shape: once per head per game (the com
		// head sat off three days on a layout mismatch with nothing in the log)
		if (gNnOffSaid.find(own) < 0) {
			gNnOffSaid.insertLast(own);
			AiLog("apex: nn-head OFF t=" + ai.teamId + " trust=" + NnF(trust0, 2)
				+ " layout=" + ((layout == NN_STATE + "|" + own) ? "ok" : "differs")
				+ " S=" + S + "/" + (st.length() + f.length()) + " own=" + own.substr(0, 40));
		}
		return 0.f;
	}
	int rule = 0;
	for (int o = 1; o < K; ++o)
		rule = (w[o] > w[rule]) ? o : rule;
	array<float> a(H);
	for (int h = 0; h < H; ++h)
		a[h] = B1[h];
	for (int i = 0; i < S; ++i) {
		const float v = (uint(i) < st.length()) ? st[i] : f[i - st.length()];
		float z = (NnSlog(v) - XM[i]) / XS[i];
		z = (z > 6.f) ? 6.f : ((z < -6.f) ? -6.f : z);
		for (int h = 0; h < H; ++h)
			a[h] += W1[h * N + i] * z;
	}
	array<float> score(K), h1(H);
	float mean = 0.f;
	for (int o = 0; o < K; ++o) {
		for (int h = 0; h < H; ++h)
			h1[h] = a[h];
		for (int i = 0; i < O; ++i) {
			const float x = (i < K) ? ((i == o) ? 1.f : 0.f) : ((i - K == rule) ? 1.f : 0.f);
			float z = (x - XM[S + i]) / XS[S + i];
			z = (z > 6.f) ? 6.f : ((z < -6.f) ? -6.f : z);
			for (int h = 0; h < H; ++h)
				h1[h] += W1[h * N + S + i] * z;
		}
		float sc = BO;
		for (int h2 = 0; h2 < H; ++h2) {
			float acc = B2[h2];
			for (int h = 0; h < H; ++h) {
				if (h1[h] > 0.f)
					acc += W2[h2 * H + h] * h1[h];
			}
			if (acc > 0.f)
				sc += WO[h2] * acc;
		}
		score[o] = sc;
		mean += sc;
	}
	mean /= float(K);
	float meanLw = 0.f;
	for (int o = 0; o < K; ++o)
		meanLw += log(w[o]);
	meanLw /= float(K);
	for (int o = 0; o < K; ++o) {
		float d = score[o] - mean;
		d = (d > 3.f) ? 3.f : ((d < -3.f) ? -3.f : d);
		w[o] = pow(2.7182818f, meanLw + (1.f - t) * (log(w[o]) - meanLw) + t * d);
	}
	return t;
}

// THE BARb PRIOR (tools/imitate.py, NNI_*): how likely BARb, in our situation,
// would build each class next. Options are tilted toward it in log space by
// apex_nn_imitate -- what a stronger AI does as a starting point the outcome
// nets then correct.
const string NNI_EXPECT = "min,mInc,eInc,mex,energy,convert,store,plant,nano,protect,airdef,army";
array<float> gNnImitLp;
int gNnImitAt = -1;
uint gNnImitN = 0;

bool NnImitLogP()
{
	if (gNnImitAt == ai.frame)
		return gNnImitLp.length() == uint(NNI_C);
	gNnImitAt = ai.frame;
	gNnImitLp.resize(0);
	const int F = NNI_F, H = NNI_H, C = NNI_C;
	if (!NNI_ON || (NNI_FEATURES != NNI_EXPECT) || (C != NC_N) || (F != 12)
		|| (NNI_W1.length() != uint(H * F)) || (NNI_W2.length() != uint(H * H))
		|| (NNI_W3.length() != uint(C * H)))
		return false;
	NnHoldings();
	array<float> x = {float(ai.frame) / 1800.f, Eco::MInc(), Eco::EInc(), gNnClassN[NC_MEX],
		gNnClassN[NC_ENERGY], gNnClassN[NC_CONVERT], gNnClassN[NC_STORE], gNnClassN[NC_PLANT],
		gNnClassN[NC_NANO], gNnClassN[NC_PROTECT], gNnClassN[NC_AIRDEF], Military::OurArmyNow()};
	array<float> h1(H), h2(H);
	for (int h = 0; h < H; ++h) {
		float acc = NNI_B1[h];
		for (int i = 0; i < F; ++i) {
			float z = (NnSlog(x[i]) - NNI_XM[i]) / NNI_XS[i];
			z = (z > 6.f) ? 6.f : ((z < -6.f) ? -6.f : z);
			acc += NNI_W1[h * F + i] * z;
		}
		h1[h] = (acc > 0.f) ? acc : 0.f;
	}
	for (int h = 0; h < H; ++h) {
		float acc = NNI_B2[h];
		for (int j = 0; j < H; ++j)
			acc += NNI_W2[h * H + j] * h1[j];
		h2[h] = (acc > 0.f) ? acc : 0.f;
	}
	gNnImitLp.resize(C);
	float mx = -1e30f;
	for (int c = 0; c < C; ++c) {
		float acc = NNI_B3[c];
		for (int j = 0; j < H; ++j)
			acc += NNI_W3[c * H + j] * h2[j];
		gNnImitLp[c] = acc;
		mx = (acc > mx) ? acc : mx;
	}
	float z = 0.f;
	for (int c = 0; c < C; ++c)
		z += pow(2.7182818f, gNnImitLp[c] - mx);
	for (int c = 0; c < C; ++c)
		gNnImitLp[c] = gNnImitLp[c] - mx - log(z);
	return true;
}

void NnImitate(array<Want@>@ ranked)
{
	const float imit = ai.GetTunable("apex_nn_imitate", TUNE_NN_IMITATE);
	if ((imit <= 0.f) || (ranked.length() < 2) || !NnImitLogP())
		return;
	const uint n = (ranked.length() < NN_K) ? ranked.length() : NN_K;
	array<float> lp(n);
	array<bool> has(n);
	float mean = 0.f;
	uint m = 0;
	for (uint r = 0; r < n; ++r) {
		const int c = (ranked[r].def is null) ? -1 : NnClassOf(int(ranked[r].def.id));
		has[r] = (c >= 0) && (ranked[r].value > 0.f);
		if (has[r]) {
			lp[r] = gNnImitLp[c];
			mean += lp[r];
			++m;
		}
	}
	if (m < 2)
		return;
	mean /= float(m);
	for (uint r = 0; r < n; ++r) {
		if (!has[r])
			continue;
		const float mult = pow(2.7182818f, imit * (lp[r] - mean));
		ranked[r].value *= mult;
		ranked[r].nnMult *= mult;
	}
	for (uint r = 1; r < ranked.length(); ++r) {
		Want@ w = ranked[r];
		uint at = r;
		while ((at > 0) && (ranked[at - 1].value < w.value)) {
			@ranked[at] = ranked[at - 1];
			--at;
		}
		@ranked[at] = w;
	}
	++gNnImitN;
	if (ai.frame >= gNnImitLogAt) {
		gNnImitLogAt = ai.frame + 60 * SECOND;
		string ln = "apex: nn-imitate t=" + ai.teamId + " n=" + gNnImitN + " imit=" + NnF(imit, 2) + " p:";
		for (int c = 0; c < NNI_C; ++c)
			ln += " " + NnF(pow(2.7182818f, gNnImitLp[c]), 2);
		AiLog(ln);
	}
}
int gNnImitLogAt = 0;

float gNnMaxTrust = -1.f;
void NnScore(CCircuitUnit@ unit, array<Want@>@ ranked)
{
	// what the net could see: wants forced in after this point (escorts, panics,
	// joins) carry placeholder values the market never priced
	for (uint r = 0; r < ranked.length(); ++r)
		ranked[r].nnPriced = true;
	EcoMexPush(ranked);
	NnImitate(ranked);
	if (ranked.length() < 2)
		return;
	if (!NNW_ON || gNnBad)
		return;
	const float blend = ai.GetTunable("apex_nn_blend", TUNE_NN_BLEND);
	if (blend <= 0.f)
		return;
	if (!NnWeightsFit()) {
		gNnBad = true;
		AiLog("apex: nn-score OFF t=" + ai.teamId + " weights do not fit this record's layout");
		return;
	}
	if (gNnKindSlot.length() == 0) {
		gNnKindSlot.resize(WK_TEETH + 1);
		for (uint k = 0; k < gNnKindSlot.length(); ++k) {
			gNnKindSlot[k] = -1;
			for (uint j = 0; j < NNW_KINDS.length(); ++j) {
				if (NNW_KINDS[j] == KindName(int(k)))
					gNnKindSlot[k] = int(j);
			}
		}
	}
	const double _t = Perf::T0();
	Want@ top0 = ranked[0];
	// No kind has earned trust: every score would be discarded below (2.4 ms an election).
	if (gNnMaxTrust < 0.f) {
		gNnMaxTrust = 0.f;
		for (uint k = 0; k < NNW_TRUST.length(); ++k)
			gNnMaxTrust = (NNW_TRUST[k] > gNnMaxTrust) ? NNW_TRUST[k] : gNnMaxTrust;
	}
	if ((blend > 0.f) && (gNnMaxTrust > 0.f)) {
		const int S = NNW_S, O = NNW_O, H = NNW_H, N = NNW_S + NNW_O;
		array<float> s;
		NnState(unit, s);
		gNnA.resize(H);
		for (int h = 0; h < H; ++h)
			gNnA[h] = NNW_B1[h];
		for (int i = 0; i < S; ++i) {
			float z = (NnSlog(s[i]) - NNW_XM[i]) / NNW_XS[i];
			z = (z > 6.f) ? 6.f : ((z < -6.f) ? -6.f : z);
			if (z == 0.f)
				continue;
			for (int h = 0; h < H; ++h)
				gNnA[h] += NNW_W1[h * N + i] * z;
		}
		const uint n = (ranked.length() < NN_K) ? ranked.length() : NN_K;
		const AIFloat3 up = unit.GetPos(ai.frame);
		array<array<float>> opts(n);
		float best = -1e30f, bestEta = 1e30f;
		for (uint r = 0; r < n; ++r) {
			NnOpt(ranked[r], up, opts[r]);
			best = (opts[r][0] > best) ? opts[r][0] : best;
			bestEta = (opts[r][9] < bestEta) ? opts[r][9] : bestEta;
		}
		array<float> score(n);
		gNnX.resize(O);
		gNnH1.resize(H);
		float mean = 0.f;
		for (uint r = 0; r < n; ++r) {
			const int kk = ranked[r].kind;
			const int slot = ((kk >= 0) && (uint(kk) < gNnKindSlot.length())) ? gNnKindSlot[kk] : -1;
			uint j = 0;
			for (uint k = 0; k < NNW_KINDS.length(); ++k)
				gNnX[j++] = (int(k) == slot) ? 1.f : 0.f;
			for (uint k = 0; k < NN_ONUM; ++k)
				gNnX[j++] = NnSlog(opts[r][k]);
			gNnX[j++] = NnSlog(opts[r][0] - best);
			gNnX[j++] = NnSlog(opts[r][9] - bestEta);
			gNnX[j++] = NnSlog(float(n));
			gNnX[j++] = 0.f;   // forced: a scored option never is
			for (int h = 0; h < H; ++h)
				gNnH1[h] = gNnA[h];
			for (int i = 0; i < O; ++i) {
				float z = (gNnX[i] - NNW_XM[S + i]) / NNW_XS[S + i];
				z = (z > 6.f) ? 6.f : ((z < -6.f) ? -6.f : z);
				if (z == 0.f)
					continue;
				for (int h = 0; h < H; ++h)
					gNnH1[h] += NNW_W1[h * N + S + i] * z;
			}
			float sc = NNW_BO;
			for (int h2 = 0; h2 < H; ++h2) {
				float a = NNW_B2[h2];
				for (int h = 0; h < H; ++h) {
					if (gNnH1[h] > 0.f)
						a += NNW_W2[h2 * H + h] * gNnH1[h];
				}
				if (a > 0.f)
					sc += NNW_WO[h2] * a;
			}
			score[r] = sc;
			mean += sc;
		}
		mean /= float(n);
		// THE NET'S VOTE IN LOG SPACE, by the trust each kind has earned: a
		// multiplier capped at e^3 could never swing a market gap of 100x, and
		// market prices differ by that much between kinds. Each option keeps the
		// group's mean log value; its deviation from it is the market's at
		// trust 0 and the net's (in units of outcome spread) at trust 1.
		float meanLv = 0.f;
		uint nLv = 0;
		for (uint r = 0; r < n; ++r) {
			if (ranked[r].value > 0.f) {
				meanLv += log(ranked[r].value);
				++nLv;
			}
		}
		meanLv = (nLv > 0) ? meanLv / float(nLv) : 0.f;
		for (uint r = 0; r < n; ++r) {
			if (ranked[r].value <= 0.f)
				continue;
			const int kk = ranked[r].kind;
			const int slot = ((kk >= 0) && (uint(kk) < gNnKindSlot.length())) ? gNnKindSlot[kk] : -1;
			float t = (slot >= 0) ? blend * NNW_TRUST[slot] : 0.f;
			t = (t > 1.f) ? 1.f : ((t < 0.f) ? 0.f : t);
			if (t <= 0.f)
				continue;
			float d = score[r] - mean;
			d = (d > 3.f) ? 3.f : ((d < -3.f) ? -3.f : d);
			const float lv = log(ranked[r].value);
			const float m = pow(2.7182818f, (1.f - t) * (lv - meanLv) + t * d - (lv - meanLv));
			ranked[r].value *= m;
			ranked[r].nnMult *= m;
			ranked[r].nnTilt = t * d;
		}
	}
	// DrawWeights takes the first of each category as its argmax: the whole list
	// must stay sorted, not just the scored head.
	for (uint r = 1; r < ranked.length(); ++r) {
		Want@ w = ranked[r];
		uint at = r;
		while ((at > 0) && (ranked[at - 1].value < w.value)) {
			@ranked[at] = ranked[at - 1];
			--at;
		}
		@ranked[at] = w;
	}
	++gNnScored;
	if (!(ranked[0] is top0))
		++gNnTopChanged;
	if (ai.frame >= gNnLogAt) {
		gNnLogAt = ai.frame + 60 * SECOND;
		AiLog("apex: nn-score t=" + ai.teamId + " net=" + NNW_GAMES + " blend=" + NnF(blend, 2)
			+ " explore=" + (gNnExplore ? 1 : 0) + " scored=" + gNnScored
			+ " topChanged=" + gNnTopChanged + " now " + KindName(top0.kind) + "->" + KindName(ranked[0].kind));
	}
	Perf::Add("dec.nn", _t);
}

}  // namespace Market
