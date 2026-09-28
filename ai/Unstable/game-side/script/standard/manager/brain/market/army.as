namespace Market {
//------------------------------------------------------------------------------
// THE ARMY MODEL -- one modeled quantity (value-paradigm): the army value
// worth standing. Insurance on what we own, plus matching what the enemy
// has been SEEN to field (a blind census reads low; the guard term is the
// floor that covers blindness).
//------------------------------------------------------------------------------

// Army value held in one role -- the portfolio sense. An army is role
// COVERAGE (apexearth: only ticks, pawns, rovers -- "where's the rest?");
// each next unit's gain diminishes by its role's share, so raiders
// saturate and the empty roles win the auction.
// Metal of this role standing beside a constructor rather than with the army.
// An escort is SPENT: it is somewhere out on the map minding one worker and
// cannot answer anything else.
float RoleCommitted(int role)
{
	float v = 0.f;
	for (uint e = 0; e < gEscDef.length(); ++e) {
		const int d = gEscDef[e];
		if ((d > 0) && (d <= Catalog::gDefCount) && (Catalog::gRole[d] == role))
			v += Catalog::gCostM[d];
	}
	return v;
}

// One walk answers EVERY role. RoleValue was asked once per combat role per
// election and walked the whole def table each time; the walk is a function of
// gOwnCount and the static catalog, so one pass per ownership change serves all
// of them. gOwnStamp moves whenever any count does, which is exactly when this
// answer can move.
array<float> gRoleGross;
int gRoleGrossStamp = -1;

void RoleGrossRefresh()
{
	if (gRoleGrossStamp == gOwnStamp)
		return;
	gRoleGrossStamp = gOwnStamp;
	for (uint i = 0; i < gRoleGross.length(); ++i)
		gRoleGross[i] = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		if (Catalog::gBuilder[int(d)] || (Catalog::gPower[int(d)] <= 1.f))
			continue;
		const int r = Catalog::gRole[int(d)];
		if (r < 0)
			continue;
		if (int(gRoleGross.length()) <= r)
			gRoleGross.resize(uint(r + 1));
		gRoleGross[r] += float(gOwnCount[d]) * Catalog::gCostM[int(d)];
	}
}

float RoleValue(int role)
{
	RoleGrossRefresh();
	float v = ((role >= 0) && (role < int(gRoleGross.length())))
			? gRoleGross[role] : 0.f;
	// ESCORTS ARE NOT COVERAGE. Pairing a raider to a worker zeroed the escort
	// term in RoleTarget while leaving that same raider counted here, so the
	// role gap closed at exactly the moment the free army emptied -- measured
	// `paired=5 risk=0` eight minutes in, with nothing left at home. Counting
	// only what is uncommitted is what makes escort duty ADD demand instead of
	// cancelling it (apexearth: "we assign a scout/raider to every con... we
	// need to create even more so we can also protect our structures").
	v -= RoleCommitted(role);
	return (v > 0.f) ? v : 0.f;
}

// Role TARGETS from what the enemy fields (apexearth 2026-08-23: "balance
// the army based on our needs" -- siege wants range, soak wants HP, air
// wants AA). BAR's counter mechanics, priced: AA tracks enemy air, riot
// tracks enemy raiders, skirm/arty track enemy static, assault carries the
// general line. A uniform baseline keeps a portfolio before contact.
// Exposed workers without an escort -- each is standing demand for one
// cheap raider (apexearth: "a *need* is cheap escorts for cons").
// ONE WALK, TWO READINGS. The count and the metal ran the same filter over the
// same worker list -- a GetPos and a distance per worker each -- and the
// election asks for both, twice over (EscortGain re-asks). Frame-scoped, so a
// worker that takes or drops a task mid-frame is read as it stood at the first
// ask of that frame: at most 1/30 s stale, and positions are already read at
// ai.frame.
int gExpoAt = -999999;
int gExpoN = 0;
float gExpoM = 0.f;

// HOW MUCH OF A WORKER THE GROUND IT STANDS ON WRITES OFF, 0..1: the larger
// of the risk field's expected loss over the stake horizon and where it is --
// inside the base plan's footprint nothing, on their influence a whole
// escort, anywhere else half (apexearth: escorts are for "going out to make
// more mexes or making defences and things outside our base area"). A radius
// from the farm guarded the back of a large base; the influence map read
// every mex site as ours because the builder itself, or a passing raider,
// lights it. Cached per worker: the cover sample behind HazardAt is not free
// and the fleet is walked per election.
array<int> gWkExpoAt(32001, -30000);
array<float> gWkExpoVal(32001, 0.f);
// The most exposed unescorted worker of the last refresh, for escort-diag.
float gExpoMax = 0.f;
string gExpoMaxWhy = "";
float WorkerExposureNow(CCircuitUnit@ wkr)
{
	const AIFloat3 p = wkr.GetPos(ai.frame);
	const float T = ai.GetTunable("apex_stake_horizon_s", TUNE_STAKE_HORIZON_S);
	const float risk = HazardAt(p) * ShortfallAt(p) * ((T > 1.f) ? T : 300.f);
	const float foe = ai.GetEnemyInflAt(p);
	float ground = 0.5f;
	if (Base::Inside(p))
		ground = 0.f;
	else if (foe >= 0.01f)
		ground = 1.f;
	const float e = (ground > risk) ? ground : risk;
	return (e > 1.f) ? 1.f : e;
}

float WorkerExposure(CCircuitUnit@ wkr)
{
	const int id = int(wkr.id);
	if ((id < 0) || (id >= int(gWkExpoAt.length())))
		return WorkerExposureNow(wkr);
	if (ai.frame - gWkExpoAt[id] < 3 * SECOND)
		return gWkExpoVal[id];
	gWkExpoAt[id] = ai.frame;
	gWkExpoVal[id] = WorkerExposureNow(wkr);
	return gWkExpoVal[id];
}

// A ground escort follows a ground worker; a fighter follows an air con
// (apexearth: "Even air cons should get a little fighter escort").
bool EscortableWorker(CCircuitUnit@ wkr, bool air)
{
	if ((wkr is null) || (wkr.task is null))
		return false;
	if (Catalog::gFlyer[int(wkr.circuitDef.id)] != air)
		return false;
	// A 1-metal builder is spawned (assist drones), not bought: nothing to guard.
	if (Catalog::gCostM[int(wkr.circuitDef.id)] <= 1.f)
		return false;
	return !wkr.circuitDef.IsRoleAny(Unit::Role::COMM.mask);   // his own escort
}

void ExposeRefresh()
{
	if (gExpoAt == ai.frame)
		return;
	gExpoAt = ai.frame;
	gExpoN = 0;
	gExpoM = 0.f;
	gExpoMax = 0.f;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ wkr = gWorkers[i];
		if (!EscortableWorker(wkr, false) || EscortedWorker(wkr.id))
			continue;
		const float e = WorkerExposure(wkr);
		if (e > gExpoMax) {
			gExpoMax = e;
			gExpoMaxWhy = wkr.circuitDef.GetName() + "#" + wkr.id + " far="
				+ int(wkr.GetPos(ai.frame).distance2D(Builder::gHomePos));
		}
		if (e < 0.5f)
			continue;
		++gExpoN;
		gExpoM += e * Catalog::gCostM[int(wkr.circuitDef.id)];
	}
	EscortDiag();
}

// Escorts share the rez-bot cap (apexearth 2026-09-27: one player paired 346
// and still read 415 short).
int EscortShortfall()
{
	ExposeRefresh();
	int room = RezFleetCap() - int(gEscWorker.length());
	if (room < 0)
		room = 0;
	return (gExpoN < room) ? gExpoN : room;
}

// THE METAL STANDING UNESCORTED OUTSIDE SAFE GROUND, and the share of our
// build power that is actually protected.
//
// apexearth's value math: "a con outside of our home safe territory
// immediately has 0 value and making the cheap pawn would add the pawns value
// + the constructor value back." So an escort is not worth ~one cheap unit --
// it is worth the CONSTRUCTOR IT RESTORES, and build power we walk out alone
// should be priced as the write-off it is.
float EscortMetalAtRisk()
{
	ExposeRefresh();
	return gExpoM;
}

// 1.0 when every worker is home or escorted, falling toward 0 as more of our
// build power walks out alone. Multiplies what a NEW constructor is worth:
// buying more of something that dies unattended is buying less than it costs.
int gBpProtAt = -999999;
float gBpProt = 1.f;

float BPProtectedFrac()
{
	if (gBpProtAt == ai.frame)
		return gBpProt;
	gBpProtAt = ai.frame;
	gBpProt = BPProtectedFracNow();
	return gBpProt;
}

// Frame-scoped through the wrapper above: a third walk of the worker list, on
// top of the two ExposeRefresh already folded into one.
float BPProtectedFracNow()
{
	float safe = 0.f;
	float risk = EscortMetalAtRisk();
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ wkr = gWorkers[i];
		if (wkr is null)
			continue;
		safe += Catalog::gCostM[int(wkr.circuitDef.id)];
	}
	safe -= risk;
	if (safe < 0.f)
		safe = 0.f;
	const float tot = safe + risk;
	if (tot <= 1.f)
		return 1.f;
	return safe / tot;
}

// The cheapest thing we could field that counts as eyes, in metal.
float gCheapScoutM = -1.f;
float CheapestScoutM()
{
	if (gCheapScoutM >= 0.f)
		return gCheapScoutM;
	gCheapScoutM = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d] || Catalog::gFlyer[d])
			continue;
		const CCircuitDef@ cd = Catalog::Def(d);
		if ((cd is null) || !cd.IsRoleAny(Unit::Role::SCOUT.mask))
			continue;
		if ((gCheapScoutM <= 0.f) || (Catalog::gCostM[d] < gCheapScoutM))
			gCheapScoutM = Catalog::gCostM[d];
	}
	return gCheapScoutM;
}

float RoleTarget(int role, float armyTarget)
{
	// AA is a PURE COUNTER: it has no value without enemy air, so it gets
	// no baseline share (watched: AA against a ground-only 1v1 enemy).
	if (role == int(Unit::Role::AA.type)) {
		// FRESH air only (GetEnemyCost never forgets a plane once seen --
		// 25k of AA vs an enemy that quit flying, watched 8v8), and OUR
		// SHARE of the team's counter: the census sums all enemies while
		// every ally instance would otherwise build the full answer.
		const float team = Military::TeamArmyCost();
		const float mine = aiMilitaryMgr.armyCost;
		const float share = (team > mine && team > 1.f) ? (mine / team) : 1.f;
		// Plus the fighters our own mission aircraft need beside them
		// (apexearth 2026-09-16: scouts flew out alone and died).
		return aiEnemyMgr.GetEnemyCostFresh(RT::AIR)
				* ai.GetTunable("apex_aa_match", TUNE_AA_MATCH) * share
				+ Air::CoverDemandM();
	}
	const float base = armyTarget / 6.f;   // maximum-entropy prior over combat roles
	// MY SHARE of every census-derived counter, the division the AA branch
	// above already applies: the role censuses are SIDE-WIDE, so unshared
	// they charged each of N allies with countering the whole enemy team.
	// The escort term is our-anchored and stays whole.
	const float cShr = AnswerShare();
	float counter = 0.f;
	if (role == int(Unit::Role::RAIDER.type))
		// Escort demand is the CONSTRUCTOR METAL it brings back, not a flat
		// 60 per head: a pawn beside a 200-metal con is worth the pawn plus
		// the con it stops us writing off.
		counter = EscortMetalAtRisk()
			+ (Military::EnemyCostOf(Unit::Role::SKIRM.type)
				+ Military::EnemyCostOf(Unit::Role::ARTY.type)) * 0.6f * cShr;
			// rocket bots die to what closes fast (apexearth's counter-chain)
	else if (role == int(Unit::Role::RIOT.type))
		counter = Military::EnemyCostOf(Unit::Role::RAIDER.type) * cShr;
	else if ((role == int(Unit::Role::SKIRM.type))
			|| (role == int(Unit::Role::ARTY.type)))
		counter = aiEnemyMgr.GetEnemyCost(RT::STATIC) * 0.5f * cShr;
	else if (role == int(Unit::Role::ASSAULT.type))
		counter = Military::EnemyCostOf(Unit::Role::ASSAULT.type) * cShr;
	else if (role == int(Unit::Role::SCOUT.type))
		// EYES ARE BOUGHT WHEN WE ARE BLIND. The raid director refuses for
		// want of remembered structures -- 128 asks of 130 in eight games --
		// and that refusal is demand, not a dead end (apexearth 2026-09-22:
		// "if we lack intel then we need scouts"). One scout per spot on
		// their half we know nothing about, at what the cheapest scout
		// costs; it returns to the base prior the moment anything is seen.
		counter = float(Military::IntelGapSpots()) * CheapestScoutM();
	return base + counter;
}

// The production appetite one standing line carries, metal/s -- what a
// factory's existence is WORTH beyond expansion, what its nano ring must
// absorb, and what an assist bid against it can earn. (Watched: a lab
// killed by artillery never rebuilt -- the plant want only priced open
// spots; and hot lines ran on one nano with no help.)
float LineSpend()
{
	const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	const float gap = ArmyTarget() - ArmyValue();
	float s = (gap > 0.f) ? (gap / ((fillS > 1.f) ? fillS : 180.f)) : 0.f;
	const float ovf = OverflowM();
	if (ovf > s)
		s = ovf;
	const int lines = (Factory::gFactoryCount > 0) ? Factory::gFactoryCount : 1;
	return s / float(lines);
}

// The most-asked walk in the market: the mex, nano, plant, tech, protect and
// rezzer paths all read it, want_tech five times in one proposal. A function of
// gOwnCount and the static catalog, so gOwnStamp -- which moves on every count
// change and nothing else -- is an exact key.
float gArmyVal = 0.f;
int gArmyValStamp = -1;

float ArmyValue()
{
	if (gArmyValStamp == gOwnStamp)
		return gArmyVal;
	gArmyValStamp = gOwnStamp;
	float v = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		if (Catalog::gBuilder[int(d)] || (Catalog::gPower[int(d)] <= 1.f)
			|| Catalog::gKamikaze[int(d)])
			continue;
		// A unit that cannot hit the ground is the AA role's, not the army's:
		// counted here it closed the army gap with Archangels.
		if (Catalog::gSurfT[int(d)] <= 0.01f)
			continue;
		v += float(gOwnCount[d]) * Catalog::gCostM[int(d)];
	}
	gArmyVal = v;
	return v;
}

// Is this def advanced -- T2 or better? Read off the build graph: anything a
// plant carrying the T2/T3 attribute produces. Nothing here names a unit.
array<int> gAdvKnown;

bool IsAdvancedDef(int d)
{
	if (!Catalog::ValidId(d))
		return false;
	if (int(gAdvKnown.length()) <= Catalog::gDefCount)
		gAdvKnown.resize(Catalog::gDefCount + 1);
	if (gAdvKnown[d] != 0)
		return gAdvKnown[d] > 0;
	int adv = -1;
	const array<int>@ by = Catalog::gBuiltBy[d];
	for (uint i = 0; i < by.length(); ++i) {
		if ((Factory::userData[by[i]].attr
			& (Factory::Attr::T2 | Factory::Attr::T3)) != 0) {
			adv = 1;
			break;
		}
	}
	gAdvKnown[d] = adv;
	return adv > 0;
}

// ...and its TIER, off the same build graph. Tier attributes are assigned by
// name for arm, cor AND leg in Main::AiMain, so this reads an ENEMY def as
// readily as one of ours -- which is the only tier knowledge script has.
array<int> gTierKnown;

int DefTier(int d)
{
	if (!Catalog::ValidId(d))
		return 1;
	if (int(gTierKnown.length()) <= Catalog::gDefCount)
		gTierKnown.resize(Catalog::gDefCount + 1);
	if (gTierKnown[d] != 0)
		return gTierKnown[d];
	int t = 1;
	const array<int>@ by = Catalog::gBuiltBy[d];
	for (uint i = 0; i < by.length(); ++i) {
		const int at = Factory::userData[by[i]].attr;
		if (((at & Factory::Attr::T3) != 0) && (t < 3))
			t = 3;
		else if (((at & Factory::Attr::T2) != 0) && (t < 2))
			t = 2;
	}
	gTierKnown[d] = t;
	return t;
}

// The share of the fielded army that is T2 or better -- what mobile support
// is bought against (apexearth: support units only for squads that hold T2
// or greater).
float gAdvArmyVal = 0.f;
int gAdvArmyStamp = -1;

float AdvArmyValue()
{
	if (gAdvArmyStamp == gOwnStamp)
		return gAdvArmyVal;
	gAdvArmyStamp = gOwnStamp;
	float v = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		if (Catalog::gBuilder[int(d)] || (Catalog::gPower[int(d)] <= 1.f)
			|| Catalog::gKamikaze[int(d)])
			continue;
		if (!IsAdvancedDef(int(d)))
			continue;
		v += float(gOwnCount[d]) * Catalog::gCostM[int(d)];
	}
	gAdvArmyVal = v;
	return v;
}

// ARMY COMPOSITION AS A STANDING TARGET. apexearth, across one session:
// "we keep making spiders (Recluse), they're mostly only good against
// buildings... we need multiple fatboys with snipers behind them. Please
// think 'I need tanks, and I need damage behind the tanks'"; "we make a lot
// of T1 rocket bots. Low HP units with more range... on their own they're
// garbage"; and then the shape itself -- "how many tanky units do I have?
// How many higher range units? how much in the middle? and how much high dps
// unit?"
//
// Four classes, read off unit DATA so nothing here names a unit. DPS is not
// bound to script, but the DLL builds power = sqrt(dps)*dmg^0.25*sqrt(hp+
// shield)/128, so power*power/hp recovers dps up to constants -- and every
// consumer below normalizes, so the constants do not matter.
//
// Classification is against the GAME's own mobile combat units, not against
// what we happen to own: our own army is empty at the start and a mean taken
// over nothing classifies everything as middling. Shares are measured against
// our army; the class each candidate belongs to is a fact about the unit.
const int LC_TANK = 0, LC_MID = 1, LC_REACH = 2, LC_DPS = 3, LC_N = 4;

// REZ DEMAND IS A RATE, NOT THE PILE (apexearth: "rezbots gain value when:
// there is valuable reclaim available; there are units that need repairing;
// there are units available to resurrect"). Sizing the fleet to clear the
// standing wreck value around home and the lane tracked a STOCK that grows
// with the battlefield -- and the lane half cannot drain at all, since the rez
// rules front-veto that ground. What the fleet can serve is what ARRIVES per
// second: new wrecks off the same decaying ledger AirLossRate reads, plus the
// repair backlog, which our own bots do close and so keeps a clearing horizon.
float gRezRate = 0.f, gRezRepairRate = 0.f, gRezWreckRate = 0.f;
int gRezWorkAt = -999999;
float RezRateM()
{
	if (ai.frame < gRezWorkAt + 10 * SECOND)
		return gRezRate;
	gRezWorkAt = ai.frame;
	const float h = ai.GetTunable("apex_rez_horizon", TUNE_REZ_HORIZON);
	gRezRepairRate = ai.GetOwnRepairM() / ((h > 1.f) ? h : 120.f);
	gRezWreckRate = Military::WreckRateM() - Military::RezLostRateM();
	if (gRezWreckRate < 0.f)
		gRezWreckRate = 0.f;
	gRezRate = gRezRepairRate + gRezWreckRate;
	return gRezRate;
}

// Metal one point of build power restores per second, on the army we own
// (falls back to the whole catalog before the first unit stands).
float LineMetalPerEffort()
{
	float m = 0.f, e = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || !LineCombat(di) || (Catalog::gBuildTime[di] <= 0.f))
			continue;
		m += float(gOwnCount[d]) * Catalog::gCostM[di];
		e += float(gOwnCount[d]) * Catalog::gBuildTime[di];
	}
	if (e <= 0.f) {
		for (int d2 = 1; d2 <= Catalog::gDefCount; ++d2) {
			if (!Catalog::gAvailable[d2] || !LineCombat(d2) || (Catalog::gBuildTime[d2] <= 0.f))
				continue;
			m += Catalog::gCostM[d2];
			e += Catalog::gBuildTime[d2];
		}
	}
	return (e > 0.f) ? (m / e) : 0.f;
}

bool LineCombat(int di)
{
	return Catalog::gMobile[di] && !Catalog::gBuilder[di]
		&& (Catalog::gPower[di] > 1.f) && (Catalog::gCostM[di] > 0.f)
		&& (Catalog::gHealth[di] > 0.f) && !Catalog::gKamikaze[di];
}

// PER BODY OR PER METAL. Range has always been read absolute while hp and dps
// were read per metal, so the argmax below compared three axes in two different
// units -- and per-metal hp made the Thud (7.9 hp/m) a tankier unit than the
// Tzar (4.7). What survives focus fire and splash is the body, not the ratio,
// which is what the four classes are describing (apexearth: "HP and a little
// bit of range"). Both halves read this, so they cannot disagree.
bool gLineAbsSet = false;
bool gLineAbsV = false;

bool LineAbs()
{
	// Latched: GetTunable caches its first answer in the DLL for the whole
	// game, so a tunable cannot move and re-reading it is pure call cost --
	// and this is read twice per LineClassOf, per candidate, per election.
	if (!gLineAbsSet) {
		gLineAbsSet = true;
		gLineAbsV = ai.GetTunable("apex_line_abs", TUNE_LINE_ABS) > 0.f;
	}
	return gLineAbsV;
}

float LineHpAxis(int d)
{
	return LineAbs() ? Catalog::gHealth[d]
			: (Catalog::gHealth[d] / Catalog::gCostM[d]);
}

float LineDpsAxis(int d)
{
	// Absolute mode reads the bound dps directly; the per-metal mode keeps
	// recovering it from power, which carries a sqrt of per-shot damage with it.
	if (LineAbs())
		return Catalog::gDps[d];
	return (Catalog::gPower[d] * Catalog::gPower[d] / Catalog::gHealth[d])
			/ Catalog::gCostM[d];
}

// THE FIELD REFERENCE EACH AXIS IS JUDGED AGAINST. A mean is an outlier
// statistic here in the same way a max was for FoeReach: a Korgoth at 149,000
// hp and a Behemoth at 335,000 drag mean hp to 7,741, so a Tzar at 7,800 reads
// as 1.008x the field and misses the 1.15 edge -- and with every axis pulled
// the same way, 92% of the field classified as MID, leaving the composition
// target with almost nothing to select. The median describes the field the
// units actually live in.
float LineRef(array<float>@ v)
{
	if (v.length() == 0)
		return 0.f;
	if (ai.GetTunable("apex_line_median", TUNE_LINE_MEDIAN) <= 0.f) {
		float s = 0.f;
		for (uint i = 0; i < v.length(); ++i)
			s += v[i];
		return s / float(v.length());
	}
	v.sortAsc();
	return v[v.length() / 2];
}

// Set when the refs are (re)computed; LineClassDiag runs once behind it. A
// class split that is 92% MID cannot express any composition target, and the
// only way to see that is to count it. Declared here because LineMeans below
// writes it -- a global read before its declaration is a No matching symbol
// that disables the whole variant.
bool gLineDiagWant = false;
bool gLineDiagDone = false;

// THE CLASS A DEF IS, memoised per def id. Once the refs above latch, LineMeans
// returns on its first line forever, so the class is a pure function of the def
// and of tunables the DLL freezes at first read -- and it is asked once or
// twice per candidate per election, plus once per owned def per TrackLine.
// Stored as class+1, so 0 is "not computed"; dropped when the refs are taken.
array<int> gLineClass;

float gLMeanHpm = -1.f, gLMeanDpm = 0.f, gLMeanR = 0.f, gLMeanSpc = 0.f;
void LineMeans()
{
	// Availability is frame-dependent; recompute until the field is non-empty
	// rather than latching a mean taken over nothing (see BestConvRatio).
	if (gLMeanHpm > 0.f)
		return;
	array<float> hpV, dpV, rrV, spV;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !LineCombat(d))
			continue;
		hpV.insertLast(LineHpAxis(d));
		dpV.insertLast(LineDpsAxis(d));
		rrV.insertLast(ClassRange(d));
		spV.insertLast(Catalog::gSpeed[d] / Catalog::gCostM[d]);
	}
	if (hpV.length() == 0) {
		gLMeanHpm = -1.f;   // not yet knowable; ask again next call
		return;
	}
	gLMeanHpm = LineRef(hpV);
	gLMeanDpm = LineRef(dpV);
	gLMeanR = LineRef(rrV);
	gLMeanSpc = LineRef(spV);
	gLineClass.resize(0);   // the refs the per-def class table was taken against
	gLineDiagWant = true;
}

void LineClassDiag()
{
	if (!gLineDiagWant || gLineDiagDone || (gLMeanHpm <= 0.f))
		return;
	gLineDiagDone = true;
	array<int> cnt(LC_N, 0);
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !LineCombat(d))
			continue;
		++cnt[LineClassOf(d)];
	}
	AiLog("apex: lineclass t=" + ai.teamId
		+ " abs=" + (LineAbs() ? 1 : 0)
		+ " median=" + formatFloat(ai.GetTunable("apex_line_median", TUNE_LINE_MEDIAN), "", 0, 0)
		+ " ref hp=" + formatFloat(gLMeanHpm, "", 0, 1)
		+ " dps=" + formatFloat(gLMeanDpm, "", 0, 2)
		+ " rng=" + formatFloat(gLMeanR, "", 0, 0)
		+ " | tank=" + cnt[LC_TANK] + " mid=" + cnt[LC_MID]
		+ " reach=" + cnt[LC_REACH] + " dps=" + cnt[LC_DPS]);
}

// Which of the four a unit IS: whichever axis it stands out on most. Nothing
// clearly above the field is the middle, which is a real role and not a
// leftover -- it is what holds a line together when the shields are gone.
int LineClassOf(int di)
{
	LineMeans();
	if ((gLMeanHpm <= 0.f) || !LineCombat(di))
		return LC_MID;
	if ((di >= 0) && (di < int(gLineClass.length())) && (gLineClass[di] != 0))
		return gLineClass[di] - 1;
	const float hpR = LineHpAxis(di) / gLMeanHpm;
	const float dpR = (gLMeanDpm > 0.f) ? (LineDpsAxis(di) / gLMeanDpm) : 0.f;
	// Range damped by an exponent so "a little bit of range" is expressible:
	// at 1 this is the axis as it always was, below 1 a long gun must stand
	// well clear of the field reference before it out-argmaxes a big body.
	float rR = (gLMeanR > 0.f) ? (ClassRange(di) / gLMeanR) : 0.f;
	const float rExp = ai.GetTunable("apex_line_range_exp", TUNE_LINE_RANGE_EXP);
	if ((rExp != 1.f) && (rR > 0.f))
		rR = pow(rR, rExp);
	float best = hpR;
	int cls = LC_TANK;
	if (rR > best) { best = rR; cls = LC_REACH; }
	if (dpR > best) { best = dpR; cls = LC_DPS; }
	const float edge = ai.GetTunable("apex_line_edge", TUNE_LINE_EDGE);
	const int lc = (best >= edge) ? cls : LC_MID;
	if ((di >= 1) && (di <= Catalog::gDefCount)) {
		if (int(gLineClass.length()) <= Catalog::gDefCount)
			gLineClass.resize(uint(Catalog::gDefCount + 1));
		gLineClass[di] = lc + 1;
	}
	return lc;
}

// What we actually field, by class, as shares of army metal.
array<float> gLineM(LC_N, 0.f);
array<float> gLineHp(LC_N, 0.f);   // the same holding in HIT POINTS -- see ShieldShare
int gLineAt = 59;   // phase offset -- see AiUpdate lockstep note
int gLineHoldAt = 0;
void TrackLine()
{
	if (ai.frame < gLineAt)
		return;
	gLineAt = ai.frame + 5 * SECOND;
	for (int c = 0; c < LC_N; ++c) {
		gLineM[c] = 0.f;
		gLineHp[c] = 0.f;
	}
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || !LineCombat(di))
			continue;
		gLineM[LineClassOf(di)] += float(gOwnCount[d]) * Catalog::gCostM[di];
		gLineHp[LineClassOf(di)] += float(gOwnCount[d]) * Catalog::gHealth[di];
	}
	// WHAT WE HOLD AGAINST WHAT WE ASKED FOR. The only line-class output was a
	// one-shot census of how many DEFS fall in each class, which reads exactly
	// like a holding and is not one -- it was misread as such within an hour of
	// being consulted. This prints the owned metal per class beside its target
	// share, so "are we short of reach" is a grep instead of an argument.
	if (ai.frame >= gLineHoldAt) {
		gLineHoldAt = ai.frame + 60 * SECOND;
		float tot = 0.f;
		for (int c = 0; c < LC_N; ++c)
			tot += gLineM[c];
		if (tot > 1.f) {
			AiLog(Factory::T() + "apex: linehold t=" + ai.teamId
				+ " armyM=" + int(tot)
				+ " tank=" + formatFloat(gLineM[LC_TANK] / tot, "", 0, 2)
					+ "/" + formatFloat(LineTarget(LC_TANK), "", 0, 2)
				+ " mid=" + formatFloat(gLineM[LC_MID] / tot, "", 0, 2)
					+ "/" + formatFloat(LineTarget(LC_MID), "", 0, 2)
				+ " reach=" + formatFloat(gLineM[LC_REACH] / tot, "", 0, 2)
					+ "/" + formatFloat(LineTarget(LC_REACH), "", 0, 2)
				+ " dps=" + formatFloat(gLineM[LC_DPS] / tot, "", 0, 2)
					+ "/" + formatFloat(LineTarget(LC_DPS), "", 0, 2)
				+ " (have/target)");
		}
	}
}

// For the allocation log: naming the class is what makes that line readable.
// CAN ANY PLANT WE OWN ACTUALLY PRODUCE THIS CLASS, and what does its cheapest
// member cost? Measured 2026-08-30: the team is owed reach on essentially every
// election and the asking factory is a T1 lab, which builds no reach-class unit
// at all -- so it built a Pawn, the army grew, and the debt grew with it. The
// share could never move. This is what lets the T1 lab STAND DOWN when a plant
// that can serve the debt exists (apexearth: "If T2 is available then perhaps
// the T1 lab does nothing. If T2 is not available then the T1 lab does the best
// it can").
array<float> gClassCheap(LC_N, -1.f);
int gClassCheapAt = -999999;

float ClassCheapestOwned(int cls)
{
	if ((cls < 0) || (cls >= LC_N))
		return -1.f;
	if (ai.frame < gClassCheapAt)
		return gClassCheap[cls];
	gClassCheapAt = ai.frame + 10 * SECOND;
	for (int c = 0; c < LC_N; ++c)
		gClassCheap[c] = -1.f;
	for (uint u = 1; u < gOwnCount.length(); ++u) {
		const int ui = int(u);
		if ((gOwnCount[u] <= 0) || Catalog::gMobile[ui])
			continue;
		const array<int>@ bl = Catalog::BuildsOf(ui);
		if (bl.length() == 0)
			continue;
		for (uint b = 0; b < bl.length(); ++b) {
			const int bd = bl[b];
			if (!Catalog::gAvailable[bd] || !Catalog::gMobile[bd])
				continue;
			if (!LineCombat(bd))
				continue;
			const int lc = LineClassOf(bd);
			if ((lc < 0) || (lc >= LC_N))
				continue;
			const float cm = Catalog::gCostM[bd];
			if ((cm > 0.f) && ((gClassCheap[lc] < 0.f) || (cm < gClassCheap[lc])))
				gClassCheap[lc] = cm;
		}
	}
	return gClassCheap[cls];
}

string LineClassName(int cls)
{
	if (cls == LC_TANK)  return "tank";
	if (cls == LC_MID)   return "mid";
	if (cls == LC_REACH) return "reach";
	if (cls == LC_DPS)   return "dps";
	return "?";
}

// The four base shares are tunables and the DLL freezes a tunable at its first
// read, so they are taken once. The adapted answer is taken once per frame:
// LineShortfall asks LineTarget once per class per candidate, which was five
// GetTunable calls and an enemy census per product on every line's election.
// Frame-scoped, so an enemy sighting lands on the next frame at the latest.
bool gLtSet = false;
float gLtTank = 0.f, gLtMid = 0.f, gLtReach = 0.f, gLtDps = 0.f, gLtAdapt = 0.f;
array<float> gLtOut(LC_N, 0.25f);
int gLtAt = -999999;

float LineTarget(int cls)
{
	if (gLtAt != ai.frame) {
		gLtAt = ai.frame;
		LineTargetRefresh();
	}
	return ((cls >= 0) && (cls < LC_N)) ? gLtOut[cls] : gLtOut[LC_DPS];
}

void LineTargetRefresh()
{
	if (!gLtSet) {
		gLtSet = true;
		gLtTank = ai.GetTunable("apex_line_tank", TUNE_LINE_TANK);
		gLtMid = ai.GetTunable("apex_line_mid", TUNE_LINE_MID);
		gLtReach = ai.GetTunable("apex_line_reach", TUNE_LINE_REACH);
		gLtDps = ai.GetTunable("apex_line_dps", TUNE_LINE_DPS);
		gLtAdapt = ai.GetTunable("apex_line_adapt", TUNE_LINE_ADAPT);
	}
	float tank = gLtTank;
	float mid = gLtMid;
	float reach = gLtReach;
	float dps = gLtDps;
	// COMPOSITION ADAPTS TO WHAT THEY FIELD (apexearth 2026-08-29: "Im ok
	// with composition adapting to the needs in the game"). The shares above
	// are the BASE; the enemy's observed STATIC share of fielded metal bends
	// reach up -- porc is farmed from beyond its reach, and the more of
	// their metal stands still, the more of ours should outrange it.
	// Renormalized, so a tilt is never a cap on any other class. More terms
	// follow this shape as they earn their measurements.
	const float adapt = gLtAdapt;
	if (adapt > 0.f) {
		const float fs = aiEnemyMgr.GetEnemyCost(RT::STATIC);
		const float fm = Military::EnemyArmyCost();
		if (fs + fm > 1.f)
			reach *= 1.f + adapt * (fs / (fs + fm));
	}
	const float tot = tank + mid + reach + dps;
	if (tot > 0.f) {
		gLtOut[LC_TANK] = tank / tot;
		gLtOut[LC_MID] = mid / tot;
		gLtOut[LC_REACH] = reach / tot;
		gLtOut[LC_DPS] = dps / tot;
	} else {
		for (int c = 0; c < LC_N; ++c)
			gLtOut[c] = 0.25f;
	}
}

// How far below its target a class is, 0..1. Proportional, never a veto
// (apexearth's call): a class at half its share is worth about twice as much
// per metal, a class at target is worth no extra, and one over target simply
// stops being favoured. Tanks die first, so their share falls and this pulls
// straight back to them -- which is also what stops reach units piling up.
float LineShortfall(int cls)
{
	TrackLine();
	float tot = 0.f;
	for (int c = 0; c < LC_N; ++c)
		tot += gLineM[c];
	if (tot <= 1.f)
		return 1.f;   // nothing fielded: every class is wanted
	const float share = gLineM[cls] / tot;
	const float want = LineTarget(cls);
	if (want <= 0.f)
		return 0.f;
	const float miss = (want - share) / want;
	return (miss > 0.f) ? ((miss > 1.f) ? 1.f : miss) : 0.f;
}

// ASSUME THEY BUILT THE FASTEST THING THEY COULD (apexearth: "in the early
// game enemy units will be FAST. assume they'll make the fastest units").
// The fastest ground combat unit the GAME offers is the bar, not a mean over
// what we happen to have seen -- the whole point is that the assumption has to
// hold while we are blind, which is exactly when raiders arrive. A unit slower
// than this cannot catch what is eating our mexes, whatever else it is good
// at. Air is excluded: it is a different answer to a different problem.
float gFoeSpeedCap = -1.f;
float FoeSpeedCap()
{
	// Availability is frame-dependent; a zero must never be cached (see
	// BestConvRatio).
	if (gFoeSpeedCap > 0.f)
		return gFoeSpeedCap;
	gFoeSpeedCap = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !LineCombat(d) || Catalog::gFlyer[d])
			continue;
		if (Catalog::gSpeed[d] > gFoeSpeedCap)
			gFoeSpeedCap = Catalog::gSpeed[d];
	}
	if (gFoeSpeedCap < 1.f)
		gFoeSpeedCap = 100.f;
	return gFoeSpeedCap;
}

// COVERAGE IS QUANTITY TIMES SPEED (apexearth: "security coverage requires
// quantity and speed"). One expensive unit cannot be in two places, and a
// spread base is many places. To shadow raiders across the ground we hold
// takes roughly one body as fast as they are per thing worth hitting, so the
// need is our standing sites times the speed we must match, and what we have
// is the ground speed we field. Falls to zero as the fleet fills, so it buys
// bodies while we are thin and stops on its own -- and it is a want, never a
// cap on anything bigger.
// Both def-table walks are functions of gOwnCount and the static catalog, so
// one pass per ownership change answers them; the spot ledger and the posted
// guards' own reading stay live.
float gPatSites = 0.f, gPatHave = 0.f;
int gPatStamp = -1;

void PatrolCensus()
{
	if (gPatStamp == gOwnStamp)
		return;
	gPatStamp = gOwnStamp;
	gPatSites = 0.f;
	gPatHave = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if (gOwnCount[d] <= 0)
			continue;
		if (Catalog::gMobile[di]) {
			if (LineCombat(di) && !Catalog::gFlyer[di])
				gPatHave += float(gOwnCount[d]) * Catalog::gSpeed[di];
			continue;
		}
		if ((Catalog::gMakeE[di] > 1.f) || (Catalog::gBuildsList[di].length() > 0))
			gPatSites += float(gOwnCount[d]);
	}
}

// The patrol half alone: ground-seen against ground-to-see, which the
// screen units bought against it fill and so saturate. The posted-guard
// share (CoverShort) never fell for them -- a scout escorting a constructor
// or dead in the field holds no post (commit 3351e3d0).
float PatrolMiss()
{
	PatrolCensus();
	const float sites = float(gLSpot.length()) + gPatSites;
	if (sites < 1.f)
		return 0.f;
	const float have = gPatHave;
	const float need = sites * FoeSpeedCap();
	if (need <= 0.f)
		return 0.f;
	float miss = 1.f - have / need;
	return (miss > 0.f) ? ((miss > 1.f) ? 1.f : miss) : 0.f;
}

float PatrolShort()
{
	const float miss = PatrolMiss();
	// The posted guard's own reading of the same shortfall: the share of the
	// base's worth no unit or turret covers (military/guardposts.as).
	const float cover = Military::CoverShort();
	return (cover > miss) ? cover : miss;
}

// CAN THIS UNIT HOLD A GUARD POST AT ALL?
//
// The same test Military::CoverUnitDef uses to decide what the coverage need is
// DENOMINATED in -- so the thing we price and the thing we ask for are the same
// class of unit. A flyer cannot stand on a building, and something with no
// surface weapon cannot answer what walks up to one; CoverPerMetal is only
// speed over cost, which an aircraft or a cheap AA bot wins outright while
// covering nothing.
//
// Without this, coverage priced and role-weighted every candidate alike, and
// bought 1,730 metal of anti-air against an enemy with no aircraft
// (production.as, 2026-09-08).
bool CoverCapable(int di)
{
	return Catalog::gAvailable[di] && Catalog::gMobile[di] && !Catalog::gFlyer[di]
		&& !Catalog::gBuilder[di] && LineCombat(di)
		&& (Catalog::gSurfT[di] > 0.01f);
}

// Ground a unit can cover per metal spent, against the field's own mean.
float CoverPerMetal(int di)
{
	LineMeans();
	if ((gLMeanSpc <= 0.f) || (Catalog::gCostM[di] <= 0.f))
		return 1.f;
	return (Catalog::gSpeed[di] / Catalog::gCostM[di]) / gLMeanSpc;
}

// WHAT A PLANT'S LINE IS WORTH, against the field. A plant is bought for what
// its CONSTRUCTOR unlocks, and two plants can unlock exactly the same thing --
// a hovercraft platform's con reaches mohos just as a T2 bot lab's does -- at
// which point the cheaper one wins on price alone and we buy a line of units
// that are not tough for their metal (apexearth: "yes it has mobility but the
// units are generally not as tough for their price... I don't want to see us
// making hovers on a land only map like the one I'm on").
//
// Combat worth per metal across the plant's mobile combat products, against
// the game-wide mean of the same. No unit is named and no map type is tested:
// a line that trades badly is worth less wherever it is built, and a line that
// trades well is unaffected.
float gCpmMean = -1.f;
float CombatPerMetalMean()
{
	if (gCpmMean > 0.f)
		return gCpmMean;
	float sum = 0.f;
	int n = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !LineCombat(d))
			continue;
		sum += Catalog::gPower[d] / Catalog::gCostM[d];
		++n;
	}
	if (n <= 0)
		return 1.f;   // not yet knowable; do not cache
	gCpmMean = sum / float(n);
	return gCpmMean;
}

float PlantLineWorth(int d)
{
	const float ref = CombatPerMetalMean();
	if (ref <= 0.f)
		return 1.f;
	const array<int>@ prods = Catalog::gBuildsList[d];
	float sum = 0.f;
	int n = 0;
	for (uint i = 0; i < prods.length(); ++i) {
		const int pd = prods[i];
		if (!Catalog::gAvailable[pd] || !LineCombat(pd))
			continue;
		sum += Catalog::gPower[pd] / Catalog::gCostM[pd];
		++n;
	}
	if (n <= 0)
		return 1.f;   // a pure constructor plant is judged on its unlock alone
	return (sum / float(n)) / ref;
}

// Share of the line that can absorb for the rest -- what makes a fragile
// long-range unit worth its range at all.
// WHAT IS STANDING IN FRONT, MEASURED IN HIT POINTS, NOT IN METAL.
//
// This was (tankMetal + midMetal) / totalMetal, and metal share is the wrong
// currency for "is there something to hide behind". apexearth's own siege ball
// -- 1 Mammoth, 10 Sheldons, 5 Arbiters -- is 2,200 of 9,300 metal, so the old
// measure scored it 0.24 and priced its reach units at a quarter strength,
// while a homogeneous Thug ball scores ~1.0 and reads fully shielded. Both
// readings are backwards: two Thugs at the same range protect nothing from each
// other, and one 15,600hp Mammoth screens fifteen units costing four times its
// price. In hit points that same ball reads 0.56.
//
// Hit points are what absorbs, so hit points are the unit of account. The class
// split is unchanged -- TANK and MID are the rows that stand in front, REACH
// and DPS are what they are standing in front OF.
float ShieldShare()
{
	TrackLine();
	float tot = 0.f;
	for (int c = 0; c < LC_N; ++c)
		tot += gLineHp[c];
	if (tot <= 1.f)
		return 0.f;
	return (gLineHp[LC_TANK] + gLineHp[LC_MID]) / tot;
}

// THE REAR SPECIALIST (apexearth 2026-08-23): in a big team game one
// player starts obviously farther from the enemy than everyone else.
// Fighting from there wastes walk time; scaling from there compounds.
// That player suppresses the army market -- the freed spend rides the
// existing eco ladder to fusions/AFUS/gantry -- and its late army budget
// carries a QUALITY bias so it buys the biggest units its labs offer
// (T3, heavy air) instead of T1/T2 it would never deliver in time.
// Election: allies' homes off the team blackboard; the enemy reference is
// the ally centroid mirrored through map center (symmetric starts, no
// sighting needed). The seat is the most SHELTERED home, not the farthest:
// distance from the enemy point rewards standing out to the side, and the
// corner is where humans attack (apexearth 2026-09-27, Colorado 8v8).
bool gEcoRole = false;

float EcoCross(float ox, float oz, float ax, float az, float bx, float bz)
{
	return (ax - ox) * (bz - oz) - (az - oz) * (bx - ox);
}

float EcoSegDist(float px, float pz, float ax, float az, float bx, float bz)
{
	const float dx = bx - ax;
	const float dz = bz - az;
	const float ll = dx * dx + dz * dz;
	float t = (ll > 0.f) ? (((px - ax) * dx + (pz - az) * dz) / ll) : 0.f;
	t = (t < 0.f) ? 0.f : ((t > 1.f) ? 1.f : t);
	const float qx = ax + t * dx - px;
	const float qz = az + t * dz - pz;
	return sqrt(qx * qx + qz * qz);
}

// How far an attack must come through the team's own ground to reach each
// home: the distance to the nearest edge of the homes' convex hull that faces
// the enemy or a flank. Only edges facing away from the enemy (the back) do
// not count. A line abreast has no inside, so there it is the distance to the
// nearer end of the line.
array<float>@ EcoShelter(const array<float>& in hx, const array<float>& in hz,
		float ex, float ez)
{
	const uint n = hx.length();
	array<float> shel(n, 0.f);
	array<uint> ord;
	for (uint i = 0; i < n; ++i) {
		ord.insertLast(i);
		uint j = ord.length() - 1;
		while ((j > 0) && ((hx[ord[j - 1]] > hx[i])
				|| ((hx[ord[j - 1]] == hx[i]) && (hz[ord[j - 1]] > hz[i])))) {
			ord[j] = ord[j - 1];
			--j;
		}
		ord[j] = i;
	}
	array<uint> h;
	if (n >= 3) {
		for (uint k = 0; k < n; ++k) {
			while ((h.length() >= 2) && (EcoCross(hx[h[h.length() - 2]], hz[h[h.length() - 2]],
					hx[h[h.length() - 1]], hz[h[h.length() - 1]], hx[ord[k]], hz[ord[k]]) <= 0.f))
				h.removeLast();
			h.insertLast(ord[k]);
		}
		const uint lower = h.length() + 1;
		for (int k = int(n) - 2; k >= 0; --k) {
			while ((h.length() >= lower) && (EcoCross(hx[h[h.length() - 2]], hz[h[h.length() - 2]],
					hx[h[h.length() - 1]], hz[h[h.length() - 1]], hx[ord[k]], hz[ord[k]]) <= 0.f))
				h.removeLast();
			h.insertLast(ord[k]);
		}
		h.removeLast();
	}
	if (h.length() < 3) {
		if (n < 2)
			return shel;
		const uint a = ord[0];
		const uint b = ord[n - 1];
		for (uint i = 0; i < n; ++i) {
			const float da = sqrt((hx[i] - hx[a]) * (hx[i] - hx[a]) + (hz[i] - hz[a]) * (hz[i] - hz[a]));
			const float db = sqrt((hx[i] - hx[b]) * (hx[i] - hx[b]) + (hz[i] - hz[b]) * (hz[i] - hz[b]));
			shel[i] = (da < db) ? da : db;
		}
		return shel;
	}
	for (uint i = 0; i < n; ++i)
		shel[i] = -1.f;
	for (uint e = 0; e < h.length(); ++e) {
		const uint a = h[e];
		const uint b = h[(e + 1) % h.length()];
		// The hull winds counter-clockwise, so (dz, -dx) points shel.
		const float nx = hz[b] - hz[a];
		const float nz = hx[a] - hx[b];
		const float mx = 0.5f * (hx[a] + hx[b]);
		const float mz = 0.5f * (hz[a] + hz[b]);
		if (nx * (ex - mx) + nz * (ez - mz) < 0.f)
			continue;
		for (uint i = 0; i < n; ++i) {
			const float d = EcoSegDist(hx[i], hz[i], hx[a], hz[a], hx[b], hz[b]);
			if ((shel[i] < 0.f) || (d < shel[i]))
				shel[i] = d;
		}
	}
	for (uint i = 0; i < n; ++i)
		if (shel[i] < 0.f)
			shel[i] = 0.f;
	return shel;
}
bool gEcoDiagDone = false;
int gEcoRoleAt = -999999;

// How much of the eco seat this AI has been told to play, 0 = decide normally.
// Clamped so a value above 1 cannot ask for more eco than the seat's own
// target, which is the thing the rest of the role is scaled against.
float EcoForce()
{
	const float v = ai.GetTunable("apex_eco_force", TUNE_ECO_FORCE);
	return (v <= 0.f) ? 0.f : ((v > 1.f) ? 1.f : v);
}
bool EcoRoleActive()
{
	// DISABLED BY HIS RULING (2026-08-29, watching: "Let's disable the eco
	// role for now because it does *not* work"). The election, the army
	// suppression and the quality bias all sit behind this one gate;
	// apex_eco_role=1 re-arms the whole machinery for a future experiment.
	// FORCED SEAT. Above 0 this AI is the eco player whatever the team's size
	// or shape -- the rear-most election below cannot seat anyone in a 1v1 or
	// a 4v4, and the point of the setting is to say "this one ecos" and watch
	// it. How far it ecos is EcoRoleTargetM, not here.
	if (EcoForce() > 0.f) {
		gEcoRole = true;
		return true;
	}
	if (ai.GetTunable("apex_eco_role", TUNE_ECO_ROLE) < 0.5f) {
		gEcoRole = false;
		return false;
	}
	if (ai.frame < gEcoRoleAt + 10 * SECOND)
		return gEcoRole;
	gEcoRoleAt = ai.frame;
	EcoStatusLog();
	const bool was = gEcoRole;
	gEcoRole = false;
	if (!Builder::gHomeSet)
		return false;
	array<Id>@ mates = ai.GetTeamIds();
	// NOT IN A 4v4. apexearth 2026-09-02: "In a 4v4 we just don't want to have
	// a player in the eco role." A four-player team has no seat far enough
	// from the fighting to be worth giving up its army and defence -- the
	// margin test below says the same thing on a line-abreast start, and this
	// says it for the team size regardless of how the start is shaped.
	if ((mates is null) || (mates.length() <= 4))
		return false;
	array<float> hx, hz;
	array<int> ht;
	float cx = 0.f, cz = 0.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const float x = ai.ReadTeamValue(int(mates[i]), "homex", -1.f);
		const float z = ai.ReadTeamValue(int(mates[i]), "homez", -1.f);
		if ((x < 0.f) || (z < 0.f))
			continue;
		ht.insertLast(int(mates[i]));
		hx.insertLast(x);
		hz.insertLast(z);
		cx += x;
		cz += z;
	}
	if (hx.length() < 4)
		return false;
	// Mates publish their homes over the first frames; an election on a
	// partial roster seated the wrong team at frame 6 (and its one-shot
	// diag lied). A non-Apex ally never publishes, so the wait is bounded.
	if ((hx.length() < mates.length()) && (ai.frame < 30 * SECOND))
		return was;
	cx /= float(hx.length());
	cz /= float(hx.length());
	const float ex = float(AiTerrainWidth()) - cx;
	const float ez = float(AiTerrainHeight()) - cz;
	gEcoRefX = ex;
	gEcoRefZ = ez;
	array<float> ds;
	for (uint i = 0; i < hx.length(); ++i) {
		const float dx = hx[i] - ex;
		const float dz = hz[i] - ez;
		ds.insertLast(dx * dx + dz * dz);
	}
	array<float>@ sh = EcoShelter(hx, hz, ex, ez);
	// Every ally computes the same roster in the same order, so a strict >
	// seats exactly one even on a tie.
	uint seat = 0;
	for (uint i = 1; i < hx.length(); ++i)
		if (sh[i] > sh[seat])
			seat = i;
	const float seatD = ds[seat];
	ds.sortAsc();
	const float dmed = ds[ds.length() / 2];
	const float margin = ai.GetTunable("apex_eco_rear_margin", TUNE_ECO_REAR_MARGIN);
	// An eight-player team seats whatever the margin (docs/24 2026-09-13); the
	// margin was for the 4v4 line-abreast start, which the size gate above
	// refuses, and a line-abreast 8v8 never reaches it.
	gEcoRole = (ht[seat] == ai.teamId) && (sh[seat] > 0.f) && (dmed > 1.f)
		&& ((mates.length() >= 8) || (seatD >= dmed * margin * margin));
	if (!gEcoDiagDone) {
		gEcoDiagDone = true;
		string row = "";
		for (uint i = 0; i < hx.length(); ++i)
			row += " t" + ht[i] + "=" + int(sh[i]);
		AiLog("apex: rear-elect homes=" + hx.length() + " seat=t" + ht[seat]
				+ " shelter" + row + " seatDist=" + sqrt(seatD)
				+ " median=" + sqrt(dmed));
	}
	if (gEcoRole != was) {
		AiLog("apex: rear-specialist " + (gEcoRole ? "ON" : "off")
				+ " team=" + ai.teamId
				+ " shelter=" + int(sh[seat]) + " seat=t" + ht[seat]);
		// A chat line survives on screen; log lines scroll away (apexearth).
		ai.SendChat(gEcoRole
				? ("I am the eco specialist (team " + ai.teamId
					+ ", sheltered position): scaling economy, no army until T3.")
				: ("Eco specialist role off (team " + ai.teamId + ")."));
	}
	return gEcoRole;
}

// The specialist's exemption ends when the war reaches it: a KNOWN front
// inside the safe radius restores every normal response.
// Danger is ENEMY AT THE DOOR, not geometry: front-line distance read
// structurally true in a packed team box (audited: the exempted specialist
// built 8.6k army, 510 defence, teched LAST -- quiet mode never engaged).
// Sustained presence arms danger; one clear read disarms. A single plane
// overflight flipped quiet mode for one refresh and bought dragon-claw
// towers at 13m (audited flicker -- danger=0 at every 2-min sample).
int gEcoDangerStreak = 0;
int gEcoDangerTickAt = 41;   // phase offset -- see AiUpdate lockstep note
bool gEcoDangerArmed = false;
bool EcoDangerNear()
{
	if (!Builder::gHomeSet)
		return false;
	// The streak ticks on a CLOCK, not per call -- EcoQuiet runs many
	// times per decide sweep, so a per-call streak armed in one frame off
	// a single overflight (claw at 4.8m with danger=0 at every sample).
	if (ai.frame >= gEcoDangerTickAt) {
		gEcoDangerTickAt = ai.frame + 10 * SECOND;
		const bool hot = ai.GetEnemyCostAt(Builder::gHomePos,
					ai.GetTunable("apex_eco_safe_r", TUNE_ECO_SAFE_R))
				> ai.GetTunable("apex_eco_danger_m", TUNE_ECO_DANGER_M);
		gEcoDangerStreak = hot ? (gEcoDangerStreak + 1) : 0;
		const bool armed = gEcoDangerStreak >= 3;   // 30s sustained
		if (armed != gEcoDangerArmed)
			AiLog("apex: eco-danger " + (armed ? "ARMED" : "cleared")
					+ " team=" + ai.teamId + " f=" + ai.frame);
		gEcoDangerArmed = armed;
	}
	return gEcoDangerArmed;
}

bool EcoQuiet()
{
	return EcoRoleActive() && !EcoDangerNear();
}

// The specialist works from home: any job farther than the leash is
// someone else's (apexearth: "keep our eco cons at home... not walking
// across the map").
bool EcoFar(const AIFloat3& in p)
{
	return EcoQuiet() && Builder::gHomeSet
		&& (p.distance2D(Builder::gHomePos)
			> ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH));
}

int gEcoStatusAt = 0;
// WHAT THE REAR SPECIALIST IS TRYING TO REACH, in metal/s of economic power.
//
// apexearth 2026-08-31: "Can we get our eco player to care not about army until
// ~500m/s and then start to make military?" -- and on the number itself: "It
// has to depend on how much bonus we get maybe (?) But the point is we need to
// be REALLY BIG."
//
// He is right that a flat 500 cannot travel. It was calibrated at +100%:
// measured on Supreme Isthmus 8v8, the median player's economic power reaches
// 485 at minute 20 and 855 by minute 25, so 500 IS his "about twenty minutes"
// -- but with no bonus the same twenty minutes is roughly half that and the
// crossover would never arrive. IncomeMult() is the handicap the game itself
// publishes, the same helper that fixed extraction pricing's blind spot, so the
// base is stated at no-bonus scale and the game scales it.
//
// This is a TARGET, not a threshold: below it the eco player's target state
// names an economy and no war, so army and defence lose the auction on value
// rather than being forbidden. Above it the role stops existing and the player
// is ordinary. That is the difference from the multiplier version it replaces,
// which decided WHETHER instead of how much and was switched off for it
// (apexearth 2026-08-29: the eco role "does *not* work").
float EcoRoleTargetM()
{
	array<Id>@ mates = ai.GetTeamIds();
	const bool eight = (mates !is null) && (mates.length() >= 8);
	const float base = eight
			? ai.GetTunable("apex_eco_target_base8", TUNE_ECO_TARGET_BASE_8)
			: ai.GetTunable("apex_eco_target_base", TUNE_ECO_TARGET_BASE);
	// A forced seat ecos as far as it was told to. This target is what ends
	// the growing phase (EcoRoleGrowing) and what the army ramp is measured
	// against, so halving it is half the eco phase -- the length, not a
	// separate clock.
	const float force = EcoForce();
	return base * IncomeMult() * ((force > 0.f) ? force : 1.f);
}

// TRUE while the rear specialist is still building the economy it named --
// which is when army and defence are not in its target at all.
//
// EcoDangerNear is the valve and it is not optional: without it the eco player
// stands naked through the whole growth phase and dies to the first raid that
// gets past the line, which is the failure mode that killed this role the first
// time. Sustained enemy metal near home (30s) restores the ordinary targets.
// Once the seat, always a wing: the player that grew the team's economy is
// the one apexearth wants flying the bombers when it turns ("I want to see
// them sending the devastating bombing raids"). Latched here, read by
// Air::IsAirLead.
bool gWasEcoSeat = false;
bool EcoRoleGrowing()
{
	const bool g = EcoRoleActive() && !EcoDangerNear()
			&& (EcoPowerM() < EcoRoleTargetM());
	if (g)
		gWasEcoSeat = true;
	return g;
}

// THE SWITCH (apexearth 2026-09-21): "make enough army for a normal defence
// of ourselves and then stop making army to focus on the switch to a good T2
// economy -- upgraded mexes, fusions, advanced converters." BARb's own curve:
// army spend flat from minute 8 to 14 while its economy spend triples, then
// the T2 army. While the switch is on the army's share of the economy is not
// in the target; the cover units, the AA counter and the towers -- the
// defence of ourselves -- stay, and sustained enemy metal at home restores the
// full target the way it does for the seat. Done once the T2 economy stands,
// and done for good: a moho lost to a raid later is a rebuild, not a return
// to the switch.
bool gT2SwitchDone = false;
bool gT2SwitchWas = false;
bool gT2Rich = false;
int gT2SwitchLogAt = 0;

// A def only an advanced hand builds: no T1 hand in its builder list.
bool AdvancedOnlyDef(int d)
{
	const array<int>@ by = Catalog::gBuiltBy[d];
	if (by.length() == 0)
		return false;
	for (uint i = 0; i < by.length(); ++i) {
		const int b = by[i];
		// A levelled commander is a COMM def and so a "T1 hand", and it can
		// build the advanced converter: read that way nothing is advanced-only.
		const CCircuitDef@ bd = Catalog::Def(b);
		if ((bd !is null) && bd.IsRoleAny(Unit::Role::COMM.mask))
			continue;
		if ((b < int(Catalog::gT1Hand.length())) && Catalog::gT1Hand[b])
			return false;
	}
	return true;
}

// Home mexes upgraded (fusion and converter are reported, not waited for). The
// mexes that count are the ones a T2 hand walks to from home in
// T2_HOME_WALK_S (his ruling 2026-09-27: "Once we get our closest advanced
// metal extractors upgraded, then we can stop... It takes a long time to walk
// all these constructors out there"). The 2,500 safe radius it replaces held
// 22 spots on Carrot Mountains and read mohos=11/22 at 37 min.
const float T2_HOME_WALK_S = 30.f;
string gT2Missing = "";
bool gT2NoFus = true;
int gNextFusDiag = 0;

float T2HomeRadius()
{
	float speed = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		// A hand that can build the moho: the Fark is advanced-only and
		// faster, and it stretched home to 2,250 (22 spots) in the test game.
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[di] || !Catalog::gBuilder[di]
			|| Catalog::gFlyer[di] || !AdvancedOnlyDef(di) || !ReachesCeiling(di))
			continue;
		if (Catalog::gSpeed[di] > speed)
			speed = Catalog::gSpeed[di];
	}
	if (speed <= 0.f)
		return ai.GetTunable("apex_eco_safe_r", TUNE_ECO_SAFE_R);
	float r = speed * T2_HOME_WALK_S;
	// Never an empty set: the nearest extracting spot always counts.
	float nearest = -1.f;
	for (uint i = 0; i < gLSpot.length(); ++i) {
		if (gLExtract[i] <= 0.f)
			continue;
		const float dd = gLPos[i].distance2D(Builder::gHomePos);
		if ((nearest < 0.f) || (dd < nearest))
			nearest = dd;
	}
	if (nearest > r)
		r = nearest;
	return r;
}

bool T2EconomyStands()
{
	const float ceil = BestExtract();
	const float r = Builder::gHomeSet ? T2HomeRadius() : 0.f;
	int up = 0;
	int low = 0;
	for (uint i = 0; i < gLSpot.length(); ++i) {
		if ((gLExtract[i] <= 0.f) || !Builder::gHomeSet
			|| (gLPos[i].distance2D(Builder::gHomePos) > r))
			continue;
		if (gLExtract[i] < ceil)
			++low;
		else
			++up;
	}
	bool gen = false;
	bool conv = false;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || Catalog::gMobile[di] || !AdvancedOnlyDef(di))
			continue;
		if (Catalog::gMakeE[di] > 0.f)
			gen = true;
		if (Catalog::gConvCapacity[di] > 0.f)
			conv = true;
	}
	gT2Missing = "mohos=" + up + "/" + (up + low) + " r=" + int(r)
		+ (gen ? " fus" : " NOFUS") + (conv ? " conv" : " NOCONV");
	gT2NoFus = !gen;
	// The mexes alone end it (his call 2026-09-27): a fusion and a converter
	// come on their own, and waiting on them held one seat to 30 min.
	return (up > 0) && (low == 0);
}

// The switch names fusions as what it is FOR, but it only takes army out of
// the target -- the metal it frees goes to the draw, which buys wind.
bool T2WantsFusion()
{
	return T2SwitchOn() && gT2NoFus;
}

int gT2SwitchAt = -1;
bool gT2SwitchVal = false;
bool T2SwitchOn()
{
	if (gT2SwitchAt == ai.frame)
		return gT2SwitchVal;
	gT2SwitchAt = ai.frame;
	gT2SwitchVal = T2SwitchEval();
	return gT2SwitchVal;
}

bool T2SwitchEval()
{
	if (gT2SwitchDone || gEcoRole)
		return false;
	if (T2EconomyStands()) {
		gT2SwitchDone = true;
		AiLog("apex: t2switch DONE t=" + ai.teamId + " f=" + ai.frame
			+ " P=" + int(EcoPowerM()) + " army=" + int(ArmyValue()));
		return false;
	}
	// Overflowing metal is army the switch would only throw away (his ruling
	// 2026-09-27); not DONE, so it holds again once the bank runs dry. Released
	// on the flow alone it flapped every few seconds: the army it let in spent
	// the overflow and the next read zeroed the army target again.
	const bool danger = EcoDangerNear();
	if (WealthWaiver())
		gT2Rich = true;
	else if (aiEconomyMgr.isMetalEmpty)
		gT2Rich = false;
	const bool rich = !danger && gT2Rich;
	const bool on = !danger && !rich;
	if ((on != gT2SwitchWas) || (ai.frame >= gT2SwitchLogAt)) {
		gT2SwitchWas = on;
		gT2SwitchLogAt = ai.frame + 60 * SECOND;
		AiLog("apex: t2switch " + (on ? "on" : (rich ? "overflow" : "danger")) + " t=" + ai.teamId
			+ " P=" + int(EcoPowerM()) + " army=" + int(ArmyValue())
			+ " upD=" + int(UpDemand()) + " " + gT2Missing);
	}
	return on;
}

// HOW MUCH OF THE WAR THE GROWING SEAT ALREADY OWES: nothing to half its
// economic target, the full targets at the target, linear between. The
// seat with zero army and zero silos to the target died in every game
// (apexearth 2026-09-14: "we would do better if we made some nuclear
// missile launchers, and if we started to ramp up the army at like 500
// metal income, doesn't mean we have to go full throttle"). 1 off the role.
float EcoRoleRamp()
{
	if (!EcoRoleGrowing())
		return 1.f;
	const float t = EcoRoleTargetM();
	if (t <= 1.f)
		return 1.f;
	const float r = (EcoPowerM() - 0.5f * t) / (0.5f * t);
	// Squared: "some", not a linear march to the full targets -- linear read
	// 139k of army and 138k of defence by minute 30 at 970 income.
	return (r <= 0.f) ? 0.f : ((r >= 1.f) ? 1.f : (r * r));
}

// IS THE HANDICAP BINDING REAL? Logged once, raw, because this repo has been
// burned by a binding that quietly returned nonsense for every team
// (Game_getTeamResource*), and the crossover above now depends on this one.
bool gIncomeMultLogged = false;
void IncomeMultProbe()
{
	if (gIncomeMultLogged || (ai.frame < 30 * SECOND))
		return;
	gIncomeMultLogged = true;
	AiLog("apex: income-mult t=" + ai.teamId
		+ " raw=" + formatFloat(ai.GetGameRulesParam("ai_handicap_" + ai.teamId, -1.f), "", 0, 3)
		+ " used=" + formatFloat(IncomeMult(), "", 0, 3)
		+ " ecoTarget=" + int(EcoRoleTargetM())
		+ " P=" + int(EcoPowerM()));
}

void EcoStatusLog()
{
	if (!gEcoRole || (ai.frame < gEcoStatusAt))
		return;
	gEcoStatusAt = ai.frame + 120 * SECOND;
	AiLog("apex: eco-status team=" + ai.teamId
			+ " growing=" + (EcoRoleGrowing() ? 1 : 0)
			+ " P=" + int(EcoPowerM())
			+ "/" + int(EcoRoleTargetM())
			+ " danger=" + (EcoDangerNear() ? 1 : 0)
			+ " foeNear=" + ai.GetEnemyCostAt(Builder::gHomePos,
					ai.GetTunable("apex_eco_safe_r", TUNE_ECO_SAFE_R))
			+ " bank=" + Eco::MCur()
			+ " inc=" + Eco::MInc());
}

// THE WEALTH AN ARMY EXISTS FOR. Not everything standing: defence and lathe
// are answers to demand, not wealth that invites an attack, and both were in
// this basis while NEITHER counts toward ArmyValue. So a nano turret raised
// the army target, the wider gap bought another nano, and the same widening
// gap drove want_tech's `funded` discount toward zero -- which is the veto on
// the T2 that would actually have closed it. coverage.as and protect_target.as
// already read the economy this way; the army target did not.
float EconAssetsM()
{
	const float e = gAssetsM - gProtM - gBPM;
	return (e > 0.f) ? e : 0.f;
}

// MY SHARE OF THE TEAM'S ANSWER. EnemyArmyCost is the SIDE-WIDE census, and a
// bar derived from the whole enemy side has to be divided by the roster before
// it is charged to one player -- the law the AA role target, the static-AA
// want and Military::AllyCount already carry, which this target never got:
// each of N allies matched the entire enemy team on 1/N of the income, so the
// gap saturated and every gap consumer (production stake, plants, nanos, the
// tech discount, siege sizing) overrode the economy for the whole game.
// Income share, off the blackboard the front budget publishes: metal is what
// closes an army gap. A silent ally (a human, another AI) is imputed at the
// mean of those who publish, which makes the no-ally-publishes case an equal
// split by seats and the solo case exactly 1 -- the 1v1 arithmetic unchanged.
float gAnswerShare = 1.f;
int gAnswerShareAt = -999999;
float AnswerShare()
{
	if (ai.frame < gAnswerShareAt + 5 * SECOND)
		return gAnswerShare;
	gAnswerShareAt = ai.frame;
	gAnswerShare = 1.f;
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() <= 1))
		return gAnswerShare;
	if (ai.GetTunable("apex_ally_share", TUNE_ALLY_SHARE) < 0.5f)
		return gAnswerShare;
	const float mine = Eco::MInc();
	float team = 0.f;
	int pubs = 0;
	for (uint i = 0; i < mates.length(); ++i) {
		// A growing eco seat answers nothing: its income in the team sum
		// would hand every ally a smaller share of the counter than the
		// team actually fields.
		if ((int(mates[i]) != ai.teamId)
			&& (ai.ReadTeamValue(int(mates[i]), Military::TV_ECOSEAT, 0.f) > 0.5f))
			continue;
		const float v = ai.ReadTeamValue(int(mates[i]), Military::TV_MINC, 0.f);
		if (v <= 0.f)
			continue;
		team += v;
		++pubs;
	}
	if ((pubs <= 0) || (team <= 0.f) || (mine <= 0.f)) {
		gAnswerShare = 1.f / float(mates.length());
		return gAnswerShare;
	}
	team *= float(mates.length()) / float(pubs);
	if (team < mine)
		team = mine;
	float s = mine / team;
	gAnswerShare = (s > 1.f) ? 1.f : s;
	return gAnswerShare;
}

// HOW MUCH ARMY WE MEAN TO HOLD -- a share of the economy we have built, and
// nothing else.
//
// apexearth chose the basis outright (2026-08-31, asked what sets the army
// share: "Own economy only"), and docs/23-the-plan.md states it as the standing
// obligation the whole ETA objective runs under: "army and defence stay at
// their proper share of the economy we have built."
//
// So the enemy-matching term is gone. It read
// max(EnemyArmyCost * AnswerShare, ourTotal * enemy_prior) * match_ratio, which
// made the size of our army a function of what we could SEE -- and this repo
// has already paid for that shape once: a gate keyed on visible enemy strength
// reads "safe" exactly when we are blind. A share of our own economy is
// knowable every frame and needs no census, no prior and no answer share.
//
// SECONDS OF ECONOMIC POWER, which is the currency DefenceTarget has used
// since 2026-08-27 and the reason to reuse it: with both halves of the standing
// obligation measured the same way, "one target strategy, some even split of
// our priorities" (his words) is expressible as the two holding equal seconds,
// and the split is readable rather than buried in two different formulas. It
// scales with income at every stage, so it needs no cap and no ramp.
float ArmyTarget()
{
	// No `(hold > 0) ? hold : default` guard: GetTunable already returns the
	// compiled default when nothing overrides it, so the guard only ever
	// stopped a deliberate ZERO -- which is the control arm of the sweep.
	// The rear specialist's target names an economy and no war until it has
	// built one -- see EcoRoleGrowing. Not a suppression multiplier: the want
	// is simply not part of the state this player is trying to reach.
	if (EcoRoleGrowing())
		return ArmyTargetFull() * EcoRoleRamp();
	// The switch is meant to keep a DEFENSIVE army and then stop buying, not
	// to stand the army down: zero holds from frame 18 to the mohos, and the
	// valve meant to restore it (EcoDangerNear) compares a unit COUNT against
	// a metal threshold, so it never arms. apex_t2_army_floor > 0 holds the
	// defensive need instead, capped at the full target. See docs/27.
	if (T2SwitchOn()) {
		const float hold = ai.GetTunable("apex_t2_army_floor",
				TUNE_T2_ARMY_FLOOR);
		if (hold <= 0.f)
			return 0.f;
		const float need = Military::HoldNeedM() * hold;
		const float full = ArmyTargetFull();
		return (need > full) ? full : need;
	}
	return ArmyTargetFull();
}

// The target with NO role suppression: what the war actually asks for.
// The gantry want reads this one -- T3 is exactly what the eco role is FOR.
// EcoPowerM reads income, the conversion ceiling and the pull tracker; all three
// are constant across a sim frame, and ownership is the other input, so
// (frame, gOwnStamp) is an exact key. ArmyTarget is asked twice in one tech
// proposal and once per rezzer election, and this is what both of them cost.
bool gArmyHoldSet = false;
float gArmyHold = 0.f;
float gArmyTgtFull = 0.f;
int gArmyTgtAt = -999999;
int gArmyTgtStamp = -1;

float ArmyTargetFull()
{
	if ((gArmyTgtAt == ai.frame) && (gArmyTgtStamp == gOwnStamp))
		return gArmyTgtFull;
	gArmyTgtAt = ai.frame;
	gArmyTgtStamp = gOwnStamp;
	if (!gArmyHoldSet) {
		gArmyHoldSet = true;
		const float hold = ai.GetTunable("apex_army_eco_s", TUNE_ARMY_ECO_S);
		gArmyHold = (hold > 0.f) ? hold : 0.f;
	}
	gArmyTgtFull = EcoPowerM() * gArmyHold * Persona::Trait(Persona::T_ARMY);
	return gArmyTgtFull;
}

// WHAT THE ARMY MODEL WANTS, PER ROLE, AND WHAT IT ALREADY HAS. Nothing logged
// this, so "15 AA units and 1,875 metal against zero enemy air" (apexearth,
// watched 2026-09-07) could not be traced to a target at all. AA is a pure
// counter -- its target is enemy air cost -- so if it reads above zero with an
// empty sky, the counter is the bug; if it reads zero and the units exist
// anyway, something outside this model is buying them.
int gNextRoleLog = 0;
void RoleCensus()
{
	if (ai.frame < gNextRoleLog)
		return;
	gNextRoleLog = ai.frame + 30 * SECOND;
	const float full = ArmyTargetFull();
	string ln = "apex: rolemix armyTgt=" + int(full)
		+ " enemyAirFresh=" + int(aiEnemyMgr.GetEnemyCostFresh(RT::AIR))
		+ " enemyAirRaw=" + int(aiEnemyMgr.GetEnemyCost(RT::AIR)) + " |";
	// Bounded by the role census the model itself keeps, not by an enum symbol
	// the script surface does not expose.
	RoleGrossRefresh();
	for (int r = 0; r < int(gRoleGross.length()); ++r) {
		const float tgt = RoleTarget(r, full);
		const float have = RoleValue(r);
		if ((tgt < 1.f) && (have < 1.f))
			continue;
		ln += " r" + r + "=" + int(have) + "/" + int(tgt);
	}
	AiLog(ln);
}

// Own combat losses, decaying -- wrecks on the field are rez-bot demand.
float gLossPool = 0.f;
int gLossDecayAt = 0;
void LossNote(int defId)
{
	if (Catalog::gMobile[defId] && !Catalog::gBuilder[defId]
		&& (Catalog::gPower[defId] > 1.f))
	{
		gLossPool += Catalog::gCostM[defId];
	}
}
void LossDecay()
{
	if (ai.frame < gLossDecayAt + 10 * SECOND)
		return;
	gLossDecayAt = ai.frame;
	gLossPool *= 0.95f;   // wrecks get reclaimed, rezzed, or destroyed
}

// Round-robin over owned ceiling-reaching cons, for the guard floor-want.
uint gServeIdx = 0;
CCircuitUnit@ NextServingCon()
{
	const float ceilX = BestExtract();
	array<CCircuitUnit@> serving;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if (u is null)
			continue;
		const array<int>@ b = Catalog::BuildsOf(int(u.circuitDef.id));
		for (uint q = 0; q < b.length(); ++q) {
			if (Catalog::gExtractsM[b[q]] >= ceilX) {
				serving.insertLast(u);
				break;
			}
		}
	}
	if (serving.length() == 0)
		return null;
	gServeIdx = (gServeIdx + 1) % serving.length();
	return serving[gServeIdx];
}

// Fraction of known workers actually holding work. Idle cons mean labs and
// more cons are OVER-valued -- capability nobody uses is not capability
// (apexearth 2026-08-23: "we have cons we aren't even using so the value of
// making labs is over-estimated").
float Utilization()
{
	if (gWorkers.length() == 0)
		return 1.f;
	int busy = 0;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if ((u !is null) && (u.task !is null))
			++busy;
	}
	return float(busy) / float(gWorkers.length());
}

// Retreat pays only if the survivor gets HEALED: thresholds rise with the
// rez/repair fleet (apexearth: "we stay in the fight until death" + "rez
// bots heal our troops -- they make a big difference" -- the two are one
// design). Refreshed here as the fleet changes.
int gNextRetreatRefresh = 73;   // phase offset -- see AiUpdate lockstep note
// A def the config set to retreat 0 never retreats: the cost scale below gave
// the Epic Tumbleweed (selfd countdown 10, so not kamikaze) 0.55 and it rolled
// home to detonate in our base (apexearth 2026-09-27). -1 unread, 0/1 flag.
array<int> gRetreatNever;
void RetreatRefresh()
{
	if (ai.frame < gNextRetreatRefresh)
		return;
	gNextRetreatRefresh = ai.frame + 15 * SECOND;
	int rezzers = 0;
	for (uint d2 = 1; d2 < gOwnCount.length(); ++d2) {
		if ((gOwnCount[d2] > 0) && Catalog::gRezzer[int(d2)])
			rezzers += gOwnCount[d2];
	}
	float healBonus = 0.05f * float(rezzers);
	if (healBonus > 0.25f)
		healBonus = 0.25f;
	if (gRetreatNever.length() == 0) {
		string bombs = "";
		for (int k = 1; k <= Catalog::gDefCount; ++k)
			if (Catalog::gAvailable[k] && Catalog::gMobile[k] && Catalog::gKamikaze[k])
				bombs += " " + Catalog::Def(k).GetName();
		AiLog("apex: kamikaze-defs" + bombs);
	}
	const float scale = ai.GetTunable("apex_retreat_cost_scale", TUNE_RETREAT_COST_SCALE);
	const float rfloor = ai.GetTunable("apex_retreat_floor", TUNE_RETREAT_FLOOR);
	for (Id rd = 1; rd <= Id(Catalog::gDefCount); ++rd) {
		const int ri = int(rd);
		if (!Catalog::gMobile[ri] || Catalog::gBuilder[ri]
			|| (Catalog::gPower[ri] <= 1.f) || Catalog::gKamikaze[ri]
			|| Catalog::gRezzer[ri])
			continue;
		CCircuitDef@ rdef = ai.GetCircuitDef(rd);
		if (rdef is null)
			continue;
		if (uint(ri) >= gRetreatNever.length()) {
			const uint was = gRetreatNever.length();
			gRetreatNever.resize(uint(Catalog::gDefCount + 1));
			for (uint k = was; k < gRetreatNever.length(); ++k)
				gRetreatNever[k] = -1;
		}
		if (gRetreatNever[ri] < 0) {
			gRetreatNever[ri] = (rdef.GetRetreat() <= 0.f) ? 1 : 0;
			if ((gRetreatNever[ri] == 1) && Catalog::gAvailable[ri])
				AiLog("apex: retreat-never " + rdef.GetName());
		}
		if (gRetreatNever[ri] == 1)
			continue;
		float rt = rfloor + Catalog::gCostM[ri] / ((scale > 1.f) ? scale : 3000.f)
				+ healBonus;
		if (rt > 0.55f)
			rt = 0.55f;
		rdef.SetRetreat(rt);
	}
}

// TWO CADENCES, NOT ONE. The retreat table and the guard sweep are periodic
// housekeeping and want the slow tick; the stall answer wants the fast one --
// an energy stall is costing income every second it holds. Sharing one timer
// meant speeding the answer up also re-derived every unit's retreat threshold
// five times as often, which is not what apex_stall_answer_s is for.
int gNextStallDry = 0;
bool gStallHadAnswer = false;

// AN INTERRUPT IS A LOAN, NOT A WRITE-OFF (apexearth: "the commander making a
// few mexes, then a factory, running out of E, making a solar, and then
// deciding to make an LLT instead of going back to the factory"). Abort() ends
// the request, so the frame he left is in the orphan ledger and NOTHING binds
// him to it: ExecuteWant's finish-before-founding block only ever looks for an
// orphan of the def the market JUST picked, and the market never picks the
// plant again -- the ledger already reads one as committed. So the debt is
// carried on the borrower: what he abandoned, by frame id, paid back at his
// next free election.
//
// Ids, not handles, for the same reason the orphan ledger uses them: a frame
// that dies between the interrupt and the payment must not leave a dangling
// CCircuitUnit@ behind.
array<Id> gDebtWho;     // the builder the stall interrupted
array<Id> gDebtFrame;   // the frame it left standing

// ...AND THE LOAN HAS TO BUY WHAT IT WAS TAKEN OUT FOR. The election hoists
// energy only while nothing at all is on the way, so one turbine in flight
// hands a builder aborted FOR the stall straight back to the roulette. The
// mark says this one was taken off work for the stall; its next election owes
// that answer.
array<Id> gStallFreed;
int gDebtPaid = 0;
int gDebtDropped = 0;

void DebtDrop(uint i)
{
	gDebtWho.removeAt(i);
	gDebtFrame.removeAt(i);
}

void StallFreedNote(CCircuitUnit@ u)
{
	if (u is null)
		return;
	for (uint i = 0; i < gStallFreed.length(); ++i) {
		if (gStallFreed[i] == u.id)
			return;
	}
	gStallFreed.insertLast(u.id);
}

bool StallFreedOwed(CCircuitUnit@ u)
{
	if (u is null)
		return false;
	for (uint i = 0; i < gStallFreed.length(); ++i) {
		if (gStallFreed[i] == u.id)
			return true;
	}
	return false;
}

void StallFreedClear(CCircuitUnit@ u)
{
	if (u is null)
		return;
	for (uint i = 0; i < gStallFreed.length(); ++i) {
		if (gStallFreed[i] != u.id)
			continue;
		gStallFreed.removeAt(i);
		return;
	}
}

void DebtNote(CCircuitUnit@ u, IUnitTask@ t)
{
	if ((u is null) || (t is null))
		return;
	CCircuitUnit@ frame = t.target;
	if ((frame is null) || (frame.circuitDef is null)
		|| frame.circuitDef.IsMobile())
		return;   // nothing standing to come back to
	for (uint i = 0; i < gDebtWho.length(); ++i) {
		if (gDebtWho[i] == u.id) {
			// He was already carrying one and has now been taken off a second
			// frame: owe the newer one, which is the one he was on.
			gDebtFrame[i] = frame.id;
			return;
		}
	}
	gDebtWho.insertLast(u.id);
	gDebtFrame.insertLast(frame.id);
}

// The frame this unit owes, or null -- the LEDGER half. It settles rows (a
// frame stops being a debt for four different reasons: finished, killed,
// re-requested, adopted by somebody else, and ComOrphanById answers all four
// at once) but never spends: the enqueue that pays it lives in execute.as,
// where the spend census keeps every task-creating call site.
CCircuitUnit@ StallDebtFrame(CCircuitUnit@ unit)
{
	if (unit is null)
		return null;
	for (uint i = 0; i < gDebtWho.length(); ++i) {
		if (gDebtWho[i] != unit.id)
			continue;
		const Id fid = gDebtFrame[i];
		CCircuitUnit@ frame = ai.GetTeamUnit(fid);
		if ((frame is null) || (frame.circuitDef is null)
			|| !ComOrphanById(fid))
		{
			++gDebtDropped;
			DebtDrop(i);
			return null;
		}
		// NOT WHILE THE STALL HE WAS BORROWED FOR IS STILL ON. Paying back into
		// a live stall is the round trip twice: he would walk to the frame, be
		// interrupted off it again, and walk back. The stall clearing is what
		// makes the debt payable, and until then the frame is still in the
		// ledger for anyone whose own election lands on it.
		if (HardEStall())
			return null;
		if (Builder::ThreatFor(unit, frame.GetPos(ai.frame))
			> Builder::CON_THREAT_VETO)
		{
			++gDebtDropped;
			DebtDrop(i);   // abandoned because the ground went hot; still is
			return null;
		}
		return frame;
	}
	return null;
}

// The borrower has been handed its frame back: clear the row.
void StallDebtSettle(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	for (uint i = 0; i < gDebtWho.length(); ++i) {
		if (gDebtWho[i] == unit.id) {
			++gDebtPaid;
			DebtDrop(i);
			return;
		}
	}
}

int DebtPaid() { return gDebtPaid; }
int DebtDropped() { return gDebtDropped; }

int gStallDiagAt = 0;
void StallWatch()
{
	if (ai.frame >= gNextStallSweep) {
		gNextStallSweep = ai.frame + 5 * SECOND;
		{ double _t = Perf::T0(); RetreatRefresh(); Perf::Add("think.retreat", _t); }
		{ double _t = Perf::T0(); GuardSweep(); Perf::Add("think.guard", _t); }
	}
	if (ai.frame < gNextStallDry)
		return;
	const float everyS = ai.GetTunable("apex_stall_answer_s", TUNE_STALL_ANSWER_S);
	const int fast = int(((everyS > 0.1f) ? everyS : 1.f) * 30.f);
	// BACK OFF WHEN THERE IS NO ANSWER. Stopping at the first qualifying worker
	// only helps when one exists; a scan that finds nobody still dry-runs every
	// candidate, and that is the EXPENSIVE case -- measured, the worst single
	// call did not improve at all (18.3 -> 20.2 ms) while running it five times
	// as often nearly doubled the total. Nothing about a miss changes second to
	// second, so a miss waits for the slow tick and only a hit earns the fast
	// one.
	gNextStallDry = ai.frame + (gStallHadAnswer ? fast : (5 * SECOND));
	gStallHadAnswer = false;
	// NOT WORTH ASKING ONCE THE ENERGY ECONOMY IS REAL (apexearth: "late in the
	// game that doesn't even matter... above 400 we probably don't need it").
	// Interrupting a builder mid-task to go put down a generator answers a
	// scarcity that stops existing: at this income a stall is a transient in
	// the pull, not something a constructor should abandon work over. It is
	// also where the scan costs most -- the worker list is longest late.
	// ...unless the metal bank is full: then the stall is income thrown away,
	// not a transient (see the hoist in decide.as).
	const float eBar = ai.GetTunable("apex_stall_answer_max_e", TUNE_STALL_ANSWER_MAX_E);
	if ((eBar > 0.f) && (Eco::EInc() > eBar) && !aiEconomyMgr.isMetalFull)
		return;
	if (!HardEStall()) {
		gStallFreed.resize(0);
		return;
	}
	const double _tDry = Perf::T0();
	// HOW MANY WORKERS THE STALL IS WORTH, NOT ONE. The shortfall the answer
	// has to cover is the same number EnergyShortOfOrdered prices against:
	// headroom-scaled pull, less income, less what is already ordered. Each
	// interrupt is charged the generation its own dry-run names, so a 35/s
	// turbine against a 300/s deficit pulls the next worker too, and a fusion
	// pulls nobody else.
	float deficit = EnergyDeficitE();
	const float deficit0 = deficit;
	array<CCircuitUnit@> picks;
	// COMMANDER FIRST. The scan used to dry-run the market for EVERY worker and
	// keep the last one that qualified -- 74 ms in one call across 8 instances,
	// the largest single spike the AI had. Ordering the candidates
	// commander-first costs one name check each and keeps the preference the
	// old loop's `break` expressed, so only the cost changes.
	array<CCircuitUnit@> cand;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if ((u is null) || (u.circuitDef is null))
			continue;
		const string nm = u.circuitDef.GetName();
		if ((nm == "armcom") || (nm == "corcom") || (nm == "legcom"))
			cand.insertAt(0, u);
		else
			cand.insertLast(u);
	}
	// A WALKER FIRST, AND ONLY THEN SOMEBODY MID-BUILD. Abort() ends the
	// request, which leaves the nanoframe standing with nobody bound to it --
	// measured, 890 abandoned frames in one 60-minute game, cormex 206 of them
	// (apexearth: "we abandon things because we are *out of energy*... we
	// should be finishing the first lab we started if it is still
	// present/partially built"). A builder still walking to its site has
	// nothing sunk and is the free interrupt; one with metal already in a frame
	// is the expensive one. Same 0.01 progress law decide.as uses to hold a
	// task through re-election, applied to the interrupt that outranks it.
	//
	// Two passes rather than a veto, so a stall is still always answerable:
	// if every candidate is mid-build, the second pass takes one anyway -- and
	// only one, because that interrupt abandons a frame.
	// WHY NOBODY IS EVER INTERRUPTED. `STALL interrupt` has fired ZERO times in
	// every game measured, while apexearth watched the commander build a turret
	// through a stall. Six filters can reject a candidate and none of them said
	// so, which is this repo's dominant bug class wearing a scan's clothing.
	int rjTask = 0, rjEnergy = 0, rjProg = 0, rjSole = 0, rjCanE = 0, rjWant = 0, rjNear = 0, rjFull = 0, seen = 0;
	for (uint pass = 0; pass < 2; ++pass) {
	for (uint i = 0; i < cand.length(); ++i) {
		CCircuitUnit@ u = cand[i];
		if (u is null)
			continue;
		IUnitTask@ t = u.task;
		++seen;
		if ((t is null) || (t.GetType() != Task::Type::BUILDER)) {
			++rjTask;
			continue;
		}
		// GEO counts as an energy answer too, or the interrupt aborts the
		// very build it elected (WK_GEO executes as BuildType::GEO).
		if ((int(t.GetBuildType()) == int(Task::BuildType::ENERGY))
			|| (int(t.GetBuildType()) == int(Task::BuildType::GEO)))
			{ ++rjEnergy; continue; }
		if ((pass == 0) && (Requests::Progress(t) > 0.01f)) {
			++rjProg;
			continue;
		}
		// The only hand on a job carries the order with it: the gantry's sole
		// walker was pulled at 13.8 min and the gantry came back at 23.5.
		if (pass == 0) {
			array<CCircuitUnit@>@ crew = t.GetUnits();
			if ((crew is null) || (crew.length() <= 1)) {
				++rjSole;
				continue;
			}
		}
		// (guard/patrol holders pass straight through: their work is worth
		// ~nothing mid-stall, so the dry-run below decides.)
		// Only interrupt a unit that could actually answer with energy.
		bool canE = false;
		const array<int>@ mine = Catalog::BuildsOf(int(u.circuitDef.id));
		for (uint b = 0; b < mine.length(); ++b) {
			if (Catalog::gMakeE[mine[b]] > 1.f) {
				canE = true;
				break;
			}
		}
		if (!canE) {
			++rjCanE;
			continue;
		}
		// Dry-run the market (proposers are pure): interrupt only a unit
		// whose TOP want right now is energy -- a blind abort thrashed 73
		// times in one game, re-deciding the same mex it left.
		Want@ e = ProposeEnergy(u);
		if ((e is null) || (e.value <= 0.f)) {
			++rjWant;
			continue;
		}
		// ...AND THAT CAN START. A rung at its in-flight cap with no site
		// worth joining is refused at execution, so the freed builder falls
		// back to another job and is interrupted again -- measured, one
		// constructor aborted six times in 30 s and built nothing.
		{
			bool startable = false;
			if (e.def !is null) {
				startable = (Requests::InFlight(e.def) < Requests::EffectiveCap(e.def))
						|| (JoinBigEnergy(u, e.def) !is null);
			}
			for (uint k = 0; !startable && (k < gEAlt.length()); ++k) {
				CCircuitDef@ ad = Catalog::Def(gEAlt[k]);
				if ((ad !is null)
					&& (Requests::InFlight(ad) < Requests::EffectiveCap(ad)))
					startable = true;
			}
			if (!startable) {
				++rjFull;
				continue;
			}
		}
		// A walker CLOSER TO HIS OWN SITE than to the stall answer is not the
		// free interrupt: what he has left to pay is smaller than the walk
		// the answer demands, so finishing the trip is the cheaper path to
		// both builds (measured: a commander pulled off a nearly-finished
		// mex walk and round-tripped the map). The second pass may still
		// take him -- a stall stays answerable.
		if (pass == 0) {
			const AIFloat3 tp0 = t.GetBuildPos();
			if (OnMap(tp0) && OnMap(e.pos)) {
				const AIFloat3 up0 = u.GetPos(ai.frame);
				if (up0.distance2D(tp0) < up0.distance2D(e.pos)) {
					++rjNear;
					continue;
				}
			}
		}
		// THE SECOND PASS IS NOT FREE EITHER, and it was priced as if it were.
		// Pass 0's law is "what he has left to pay is smaller than the walk the
		// answer demands"; the same law in metal is what pass 1 never asked. A
		// commander 96% through a lab has 21 metal left and the solar he leaves
		// for costs 155, so abandoning is the SLOWER path to both buildings AND
		// it drops a frame with nothing bound to it (measured over 336 logs:
		// 605 interrupts abandoned real progress, 53 of them past 90% --
		// apexearth, watching the opening: "we will build 90% of a building and
		// then choose to do something else... a commander on the botlab").
		//
		// A DEFERRAL, NOT A VETO. What this refuses to abandon is by
		// construction cheaper to finish than the answer is to build, so the
		// stall waits LESS than the interrupt would have cost it, and he is a
		// free pass-0 candidate the moment the frame tops out. Repair and
		// reclaim hold no frame of their own (no buildDef) and stay freely
		// interruptible.
		if ((pass == 1) && (t.buildDef !is null)) {
			float done1 = Requests::Progress(t);
			if (done1 < 0.f)
				done1 = 0.f;
			else if (done1 > 1.f)
				done1 = 1.f;
			// Raw metal both sides: this is "which order finishes both sooner",
			// not a market valuation, so the want's priced mCost (displacement,
			// premiums) is the wrong side of the comparison.
			// ...in BOTH currencies. Metal alone said a light tower (85 m,
			// 680 E) was always cheaper to finish than a solar, so the builder
			// on it was never interrupted and stalled the base building it
			// (apexearth: "we usually stall building an LLT").
			// ...as ONE bill at the stall's own energy price: two tests both
			// required never held, since every T1 generator costs 0 E.
			const float ansM = (e.def !is null) ? e.def.costM : e.mCost;
			const float ansE = (e.def !is null) ? Catalog::gCostE[int(e.def.id)] : 0.f;
			const float eAt = ECostSpot();
			const float left = (1.f - done1) * (t.buildDef.costM
					+ Catalog::gCostE[int(t.buildDef.id)] * eAt);
			if (left <= ansM + ansE * eAt)
				continue;
		}
		Want@ mx = ProposeMex(u);
		if ((mx !is null) && (mx.value > e.value))
			continue;
		picks.insertLast(u);
		if (e.def !is null)
			deficit -= Catalog::gMakeE[int(e.def.id)];
		if ((deficit <= 0.f) || (pass == 1))
			break;
	}
	if (picks.length() > 0)
		break;
	}
	Perf::Add("think.stalldry", _tDry);
	if (picks.length() == 0)
		return;
	gStallHadAnswer = true;
	for (uint i = 0; i < picks.length(); ++i) {
		CCircuitUnit@ p = picks[i];
	if (ai.frame >= gStallDiagAt) {
		gStallDiagAt = ai.frame + 15 * SECOND;
		AiLog("apex: stall-scan t=" + ai.teamId
			+ " workers=" + gWorkers.length() + " seen=" + seen
			+ " picks=" + picks.length()
			+ " deficit=" + formatFloat(deficit0, "", 0, 0)
			+ " rj: task=" + rjTask + " isE=" + rjEnergy + " prog=" + rjProg + " sole=" + rjSole
			+ " canE=" + rjCanE + " want=" + rjWant + " near=" + rjNear
			+ " full=" + rjFull);
	}
		AiLog("apex: STALL interrupt -- " + p.circuitDef.GetName() + " #" + p.id
			+ " progress=" + formatFloat(Requests::Progress(p.task), "", 0, 2)
			+ " (" + (i + 1) + "/" + picks.length() + ")"
			+ " short=" + formatFloat(deficit0, "", 0, 1)
			+ " coming=" + formatFloat(EMakeInFlight(), "", 0, 1)
			+ " leaves its build to answer the energy stall");
		DebtNote(p, p.task);   // before Abort(): the task is what holds the frame
		StallFreedNote(p);
		// Abort() ends the job for the whole crew, not just this hand.
		array<CCircuitUnit@>@ crew = p.task.GetUnits();
		if ((crew !is null) && (crew.length() > 1))
			p.task.RemoveUnit(p);
		else
			p.task.Abort();
	}
}


}  // namespace Market
