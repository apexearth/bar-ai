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
	+ "shArmy,shDef,shAirdef,shEco,shBP,tgArmy,tgDef,tgAirdef,tgEco,tgBP";
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

void NnHoldings()
{
	if ((gNnHoldStamp == gComStamp) && (ai.frame - gNnHoldAt < 30))
		return;
	gNnHoldStamp = gComStamp;
	gNnHoldAt = ai.frame;
	for (uint k = 0; k < gNnHold.length(); ++k)
		gNnHold[k] = 0.f;
	for (uint i = 0; i < ComLen(); ++i) {
		const int d = gComDef[i];
		if ((d < 0) || (d >= int(Catalog::gCostM.length())) || ((gComState[i] & CS_COMING) != 0))
			continue;
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

// DISCOVERY GAMES (his 2026-10-04): in apex_nn_explore of the games that carry
// a trained net, every kind of want gets its own random multiplier for the
// whole game and the net's output layer gets noise, so we see what wanting
// more or less of each thing does -- against overfitting, for discovery.
// Rolled once per game; the roll is logged so the trainer knows.
bool gNnExploreRolled = false;
bool gNnExplore = false;
array<float> gNnKindMult;
array<float> gNnWO;

float NnGauss()
{
	float s = 0.f;
	for (int i = 0; i < 12; ++i)
		s += float(AiRandom(0, 10000)) / 10000.f;
	return s - 6.f;
}

void NnExploreRoll()
{
	if (gNnExploreRolled)
		return;
	gNnExploreRolled = true;
	gNnKindMult.resize(WK_TEETH + 1);
	for (uint k = 0; k < gNnKindMult.length(); ++k)
		gNnKindMult[k] = 1.f;
	gNnWO.resize(uint(NNW_H));
	for (int h = 0; h < NNW_H; ++h)
		gNnWO[h] = NNW_WO[h];
	const float chance = ai.GetTunable("apex_nn_explore", TUNE_NN_EXPLORE);
	gNnExplore = NNW_ON && (float(AiRandom(0, 10000)) / 10000.f < chance);
	if (!gNnExplore)
		return;
	string ln = "apex: nn-explore t=" + ai.teamId + " on |";
	for (uint k = 0; k < gNnKindMult.length(); ++k) {
		gNnKindMult[k] = pow(2.7182818f, 0.4f * NnGauss());
		ln += " " + KindName(int(k)) + "=" + NnF(gNnKindMult[k], 2);
	}
	for (int h = 0; h < NNW_H; ++h)
		gNnWO[h] = NNW_WO[h] * (1.f + 0.5f * NnGauss());
	AiLog(ln);
}

void NnRecord(CCircuitUnit@ unit, Want@ chosen, uint depth, const string& in why)
{
	if ((gNnSnapAt != ai.frame) || (gNnSnapUnit != int(unit.id)))
		return;
	const double _t = Perf::T0();
	NnExploreRoll();
	if (!gNnHeader) {
		gNnHeader = true;
		AiLog("apex: nn-schema v5 state=" + NN_STATE + " opt=" + NN_OPT + " k=" + NN_K
			+ " net=" + (NNW_ON ? NNW_GAMES : -1) + " explore=" + (gNnExplore ? 1 : 0));
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

void NnFacRecord(CCircuitUnit@ fac, const array<int>& in defs, const array<float>& in vals,
		const array<float>& in gains, float sum, uint pick)
{
	const double _t = Perf::T0();
	if (!gNnFacHeader) {
		gNnFacHeader = true;
		AiLog("apex: nnfac-schema v1 state=" + NN_STATE + " opt=def,value,gain,cm,ce,bt,tierO,ownN,p");
	}
	string ln = "apex: nnfac t=" + ai.teamId + " f=" + ai.frame + " u=" + fac.id
		+ " c=" + fac.circuitDef.GetName() + " | " + NnStateText(fac) + " |";
	const uint n = (defs.length() < 24) ? defs.length() : 24;
	for (uint i = 0; i < n; ++i) {
		const int d = defs[i];
		ln += ((i == 0) ? " " : " ; ") + Catalog::Def(d).GetName()
			+ "," + NnF(vals[i] * 1000.f, 3) + "," + NnF(gains[i], 3)
			+ "," + NnF(Catalog::gCostM[d], 0) + "," + NnF(Catalog::gCostE[d], 0)
			+ "," + NnF(Catalog::gBuildTime[d], 0) + "," + DefTier(d)
			+ "," + ((d < int(gOwnCount.length())) ? gOwnCount[d] : 0)
			+ "," + NnF((sum > 0.f) ? vals[i] / sum : 0.f, 6);
	}
	ln += " | chosen=" + ((pick < n) ? int(pick) : -1);
	AiLog(ln);
	Perf::Add("fac.nnrec", _t);
}

float NnSlog(float x)
{
	const float a = log(1.f + abs(x));
	return (x < 0.f) ? -a : a;
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
		&& (NNW_WO.length() == uint(NNW_H));
}

void NnScore(CCircuitUnit@ unit, array<Want@>@ ranked)
{
	// what the net could see: wants forced in after this point (escorts, panics,
	// joins) carry placeholder values the market never priced
	for (uint r = 0; r < ranked.length(); ++r)
		ranked[r].nnPriced = true;
	if (!NNW_ON || gNnBad || (ranked.length() < 2))
		return;
	NnExploreRoll();
	const float blend = ai.GetTunable("apex_nn_blend", TUNE_NN_BLEND);
	if ((blend <= 0.f) && !gNnExplore)
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
	if (gNnExplore) {
		for (uint r = 0; r < ranked.length(); ++r) {
			const int k = ranked[r].kind;
			if ((k >= 0) && (uint(k) < gNnKindMult.length())) {
				ranked[r].value *= gNnKindMult[k];
				ranked[r].nnMult *= gNnKindMult[k];
			}
		}
	}
	if (blend > 0.f) {
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
					sc += gNnWO[h2] * a;
			}
			score[r] = sc;
			mean += sc;
		}
		mean /= float(n);
		for (uint r = 0; r < n; ++r) {
			float d = score[r] - mean;
			d = (d > 3.f) ? 3.f : ((d < -3.f) ? -3.f : d);
			const float m = pow(2.7182818f, blend * d);
			ranked[r].value *= m;
			ranked[r].nnMult *= m;
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
