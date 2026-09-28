namespace Market {

// The best power-per-metal a factory can field, tier fades included -- the
// line's quality against the enemy it faces. 10 s memo per factory def.
array<float> gFacPPC;
array<int>   gFacPPCAt;
string gYieldLog = "";
float FacBestPPC(int facDef)
{
	if (int(gFacPPC.length()) <= Catalog::gDefCount) {
		gFacPPC.resize(uint(Catalog::gDefCount + 1));
		gFacPPCAt.resize(uint(Catalog::gDefCount + 1));
		for (uint i = 0; i < gFacPPCAt.length(); ++i)
			gFacPPCAt[i] = -999999;
	}
	if (ai.frame - gFacPPCAt[facDef] < 10 * SECOND)
		return gFacPPC[facDef];
	gFacPPCAt[facDef] = ai.frame;
	float best = 0.f;
	const array<int>@ pl = Catalog::BuildsOf(facDef);
	for (uint i = 0; i < pl.length(); ++i) {
		const int d = pl[i];
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d] || Catalog::gBuilder[d]
			|| (Catalog::gPower[d] <= 1.f) || Catalog::gKamikaze[d])
			continue;
		const float v = UnitPPC(d);
		if (v > best)
			best = v;
	}
	gFacPPC[facDef] = best;
	return best;
}

// Metal per second a factory turns into its best unit: its own build power
// plus the lathe on it, over that unit's build effort per metal.
float FacMetalRate(CCircuitUnit@ f)
{
	const int fd = int(f.circuitDef.id);
	const array<int>@ pl = Catalog::BuildsOf(fd);
	float best = 0.f;
	int bd = -1;
	for (uint i = 0; i < pl.length(); ++i) {
		const int d = pl[i];
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d] || Catalog::gBuilder[d]
			|| (Catalog::gPower[d] <= 1.f) || Catalog::gKamikaze[d])
			continue;
		const float v = UnitPPC(d);
		if (v > best) {
			best = v;
			bd = d;
		}
	}
	if ((bd < 0) || (Catalog::gBuildTime[bd] <= 1.f))
		return 0.f;
	const float bp = Catalog::gBuildPower[fd] + RingBPAt(f.GetPos(ai.frame));
	return bp * Catalog::gCostM[bd] / Catalog::gBuildTime[bd];
}

//------------------------------------------------------------------------------
// The production market's first Want: one constructor at a time while open
// expansion ground remains. Serialized by the sent-ledger, never by a count.
//------------------------------------------------------------------------------

// A "T2 con" in play terms: a constructor whose build list reaches the best
// extractor the game offers. Tracks the CEILING rather than a tier name, so
// it moves with the game rather than with a hardcoded def.
// Memoised on the ceiling itself: the answer is a function of BestExtract()
// and the static build tree, and prod.cands asks it once per owned def per
// CANDIDATE def. BestExtract latches once positive (it never caches a zero),
// so the table is rebuilt at most once.
array<int> gRcAns;
float gRcCeil = -1.f;
bool ReachesCeiling(int defId)
{
	const float ceilM = BestExtract();
	if (ceilM <= 0.f)
		return false;
	if (gRcCeil != ceilM) {
		gRcCeil = ceilM;
		gRcAns.resize(0);
		gRcAns.resize(Catalog::gDefCount + 1);
		for (uint k = 0; k < gRcAns.length(); ++k)
			gRcAns[k] = -1;
	}
	const bool memo = (defId >= 0) && (defId < int(gRcAns.length()));
	if (memo && (gRcAns[defId] >= 0))
		return gRcAns[defId] > 0;
	bool hit = false;
	const array<int>@ b = Catalog::gBuildsList[defId];
	for (uint q = 0; q < b.length(); ++q) {
		if (Catalog::gExtractsM[b[q]] >= ceilM) {
			hit = true;
			break;
		}
	}
	if (memo)
		gRcAns[defId] = hit ? 1 : 0;
	return hit;
}

// THE COMMANDER IS NOT A CONSTRUCTOR FOR THIS PURPOSE. It is mobile, it is a
// builder, and it reaches the ceiling (it builds the T1 extractor), so it
// satisfied the floor on its own from frame zero: want = 1 + inc/25 is 1.4 at
// 10 metal/s, have = 1, so need came out 0 and the line ordered NOTHING until
// income passed 25 (apexearth, watched: "we aren't making early game
// constructors. We should have 2 or 3 constructors within the first 5
// minutes"). It also has its own job -- the opening, and it cannot be replaced
// if it dies working -- so counting it as one of the crew both hides the
// shortfall and puts it in the crowd.
// Once per frame per ownership change, not once per candidate def: prod.cands
// calls this inside its candidate loop, and the walk carries a Catalog::Def
// engine call for every one of the 949 slots.
int gCcoFrame = -30000;
int gCcoOwn = -1;
int gCcoVal = 0;
int CeilingConsOwned()
{
	if ((gCcoFrame == ai.frame) && (gCcoOwn == gOwnStamp))
		return gCcoVal;
	gCcoFrame = ai.frame;
	gCcoOwn = gOwnStamp;
	// THE FLOOR IS FILLED BY FLYERS ONCE A PLANT OFFERS THEM: a walker's
	// every start costs the walk, and the floor satisfied by walkers never
	// bought the air con (apexearth 2026-09-14: "we really need to get on
	// the ball here with making air and using air cons"; the seat's T1 air
	// plant produced none).
	const bool flyLab = FlyingConLab(true);
	int n = 0;
	for (uint c = 1; c < gOwnCount.length(); ++c) {
		if ((gOwnCount[c] <= 0) || !Catalog::gMobile[int(c)]
			|| !Catalog::gBuilder[int(c)]
			|| Catalog::Def(int(c)).IsRoleAny(Unit::Role::COMM.mask))
			continue;
		if (ReachesCeiling(int(c)) && (Catalog::gFlyer[int(c)] || !flyLab))
			n += gOwnCount[c];
	}
	gCcoVal = n;
	return n;
}

// Ceiling cons ordered but not yet standing -- the factory queues plus the
// send-ledger. gOwnCount counts FINISHED units only, so without this the
// floor below re-orders for the whole build and lands a crowd.
int CeilingConsInFlight()
{
	const bool flyLab = FlyingConLab(true);
	int n = 0;
	for (uint i = 0; i < Brain::gFQPendDef.length(); ++i) {
		CCircuitDef@ pd = Brain::gFQPendDef[i];
		if ((pd !is null) && ReachesCeiling(int(pd.id))
			&& (Catalog::gFlyer[int(pd.id)] || !flyLab))
			++n;
	}
	return n;
}

// EVERY CONSTRUCTOR WE OWN, ANY TIER, EXCLUDING THE COMMANDER.
//
// CeilingConsOwned above answers a narrower question -- cons that reach
// BestExtract(), which scans every available def and so means the MOHO. No T1
// con qualifies, and neither does the commander, so that floor is a T2-con
// floor exactly as its name says: measured firing at 9.5 minutes ordering an
// armack, never in the opening. Nothing anywhere asked for constructors as
// such, which is why the opening had none and whether a player got any early
// came down to the proportional draw (measured 3v3: two teams ordered armck at
// factory picks 1-2, the third at picks 5-6, and looked from outside like it
// never built them at all).
//
// The commander is excluded because it is not one of the crew -- it has the
// opening to run and cannot be replaced if it dies working.
// Basic (non-ceiling) flying constructors: the nano-turret hands.
bool IsT1AirCon(int d)
{
	return Catalog::gMobile[d] && Catalog::gBuilder[d] && Catalog::gFlyer[d]
		&& !ReachesCeiling(d)
		&& !Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask);
}

int T1AirConsOwned()
{
	int n = 0;
	for (uint c = 1; c < gOwnCount.length(); ++c) {
		if ((gOwnCount[c] > 0) && IsT1AirCon(int(c)))
			n += gOwnCount[c];
	}
	return n;
}

int T1AirConsInFlight()
{
	int n = 0;
	for (uint i = 0; i < Brain::gFQPendDef.length(); ++i) {
		CCircuitDef@ pd = Brain::gFQPendDef[i];
		if ((pd !is null) && IsT1AirCon(int(pd.id)))
			++n;
	}
	return n;
}

int T1AirConsNeed()
{
	const int want = int(ai.GetTunable("apex_t1_air_con_min", TUNE_T1_AIR_CON_MIN));
	const int have = T1AirConsOwned() + T1AirConsInFlight();
	return (have < want) ? (want - have) : 0;
}

int ConsOwnedAny()
{
	const bool flyLab = FlyingConLab(false);   // same law as the ceiling count
	int n = 0;
	for (uint c = 1; c < gOwnCount.length(); ++c) {
		if ((gOwnCount[c] <= 0) || !Catalog::gMobile[int(c)]
			|| !Catalog::gBuilder[int(c)]
			|| Catalog::Def(int(c)).IsRoleAny(Unit::Role::COMM.mask))
			continue;
		if (Catalog::gFlyer[int(c)] || !flyLab)
			n += gOwnCount[c];
	}
	return n;
}

// Ordered but not standing. gOwnCount counts FINISHED units, and an order is
// not applied on the frame it is issued, so without this the floor re-orders
// for the whole build and lands a crowd.
int ConsInFlightAny()
{
	const bool flyLab = FlyingConLab(false);
	int n = 0;
	for (uint i = 0; i < Brain::gFQPendDef.length(); ++i) {
		CCircuitDef@ pd = Brain::gFQPendDef[i];
		if ((pd !is null) && pd.IsMobile() && pd.IsBuilder()
			&& !pd.IsRoleAny(Unit::Role::COMM.mask)
			&& (pd.IsAbleToFly() || !flyLab))
			++n;
	}
	return n;
}

// THE CONSTRUCTOR FLOOR, from apexearth's own two readings: "at like 12 income
// we still want 2 or 3 cons... often I want 3 even at just 12 income" and "at
// 100 metal per second we should have at least 5". Those two points fix the
// line: 2.7 + inc/44 gives 3.0 at 12 m/s and 5.0 at 100. Not a cap -- nothing
// stops the auction buying more when they are worth more.
// Metal per second one ordinary constructor can SPEND. The same conversion
// BPCapacity uses (build power x 7/80), over the mobile non-commander builders
// we actually own -- so it is what our own fleet is made of, not a def table
// guess. Falls back to the cheapest available builder before we own any.
float ConWorkerBP()
{
	float bp = 0.f;
	int n = 0;
	for (uint c = 1; c < gOwnCount.length(); ++c) {
		const int d = int(c);
		if ((gOwnCount[c] <= 0) || !Catalog::gMobile[d] || !Catalog::gBuilder[d]
			|| Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask))
			continue;
		bp += float(gOwnCount[c]) * Catalog::gBuildPower[d];
		n += gOwnCount[c];
	}
	if (n > 0)
		return (bp / float(n)) * (7.f / 80.f);
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (Catalog::gAvailable[d] && Catalog::gMobile[d] && Catalog::gBuilder[d]
			&& (Catalog::gBuildPower[d] > 0.f))
			return Catalog::gBuildPower[d] * (7.f / 80.f);
	}
	return 0.f;
}

// Metal per second no number of hands could spend: income less the pull the
// present fleet would exert at full energy feed.
float UnspentByHands()
{
	const float share = EFeedShare();
	const float pull = Eco::MPull() / ((share > 0.05f) ? share : 0.05f);
	return Eco::MInc() - pull;
}

// A PURE ASSIST UNIT: the Butler and the Twitcher -- a fast, unarmed
// builder a ceiling-tier lab offers BESIDE its real constructor, reaching
// only the basic tier (0.6-0.67 BP per metal at 75-90 speed against the T2
// con's 0.40 at 33). Metal we cannot spend is a shortage of LATHE, and this
// is the cheapest mobile lathe such a lab makes, so it takes the unspent
// term where it exists (apexearth 2026-09-14: "if we're thinking in terms of
// 'i need more build power' then the butler would have been the better
// choice"). Armed helpers (the spider, the spy) are not it: a first draft
// that read "lathes, no build options" bought 117 spies.
array<int> gAssistFlag;   // per def: -1 unknown, 0 no, 1 yes
bool IsAssistDef(int d)
{
	if (!Catalog::ValidId(d))
		return false;
	if (uint(d) >= gAssistFlag.length()) {
		// resize fills with 0 = "no", which memoised every def as not
		// an assist unit before a single test ran.
		const uint was = gAssistFlag.length();
		gAssistFlag.resize(uint(Catalog::gDefCount + 1));
		for (uint k = was; k < gAssistFlag.length(); ++k)
			gAssistFlag[k] = -1;
	}
	if (gAssistFlag[d] < 0) {
		bool yes = Catalog::gAvailable[d] && Catalog::gMobile[d] && Catalog::gBuilder[d]
			&& !Catalog::gFlyer[d] && (Catalog::gBuildPower[d] > 0.f)
			&& (Catalog::gDps[d] <= 0.f) && (Catalog::gCostM[d] > 1.f)
			&& !ReachesCeiling(d)
			&& !Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask);
		if (yes) {
			// ...offered beside a ceiling constructor: the T1 lab's own con
			// is a starter, not a helper.
			yes = false;
			for (int f = 1; (f <= Catalog::gDefCount) && !yes; ++f) {
				if (Catalog::gMobile[f] || (Catalog::gBuildsList[f].length() == 0))
					continue;
				const array<int>@ pr = Catalog::gBuildsList[f];
				bool mine = false, ceil = false;
				for (uint q = 0; q < pr.length(); ++q) {
					if (pr[q] == d)
						mine = true;
					else if (Catalog::gMobile[pr[q]] && Catalog::gBuilder[pr[q]]
						&& ReachesCeiling(pr[q]))
						ceil = true;
				}
				yes = mine && ceil;
			}
		}
		// Not memoised before the ceiling is known: ReachesCeiling reads
		// false for everything until BestExtract names the moho, and a "no"
		// cached then stood for the game (measured: corfast assist=0 with
		// every other flag right).
		if (BestExtract() > 0.f)
			gAssistFlag[d] = yes ? 1 : 0;
		return yes;
	}
	return gAssistFlag[d] == 1;
}

array<int> gAssistLogged;
int AssistDefOf(int facDef)
{
	int best = -1;
	float bestPerM = 0.f;
	const array<int>@ pr = Catalog::BuildsOf(facDef);
	// Once per plant def: which product qualifies and why not (the first
	// draft bought spies; the second bought nothing and nobody could say why).
	const bool logNow = (gAssistLogged.find(facDef) < 0);
	if (logNow)
		gAssistLogged.insertLast(facDef);
	for (uint q = 0; q < pr.length(); ++q) {
		const int d = pr[q];
		if (logNow && Catalog::gMobile[d] && Catalog::gBuilder[d]) {
			AiLog("apex: assistdef t=" + ai.teamId + " lab=" + Catalog::Def(facDef).GetName()
				+ " " + Catalog::Def(d).GetName()
				+ " avail=" + (Catalog::gAvailable[d] ? 1 : 0)
				+ " fly=" + (Catalog::gFlyer[d] ? 1 : 0)
				+ " bp=" + int(Catalog::gBuildPower[d])
				+ " dps=" + formatFloat(Catalog::gDps[d], "", 0, 2)
				+ " ceil=" + (ReachesCeiling(d) ? 1 : 0)
				+ " assist=" + (IsAssistDef(d) ? 1 : 0));
		}
		if (!IsAssistDef(d))
			continue;
		const float perM = Catalog::gBuildPower[d] / Catalog::gCostM[d];
		if (perM > bestPerM) {
			bestPerM = perM;
			best = d;
		}
	}
	return best;
}

// Does a standing plant of ours offer a FLYING constructor (of the ceiling
// tier when asked)? The floors are rules that fill from whichever lab asks
// first, and the bot lab asks most; a walker's every start costs the walk
// (apexearth 2026-09-14: "we're not making the air cons we need to really
// scale and build fast without the slow walking being an issue"). While a
// plant offers the flyer, the walking labs leave the floor to it.
bool FlyingConLab(bool ceiling)
{
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if (f is null)
			continue;
		const array<int>@ pr = Catalog::BuildsOf(int(f.circuitDef.id));
		for (uint q = 0; q < pr.length(); ++q) {
			const int d = pr[q];
			if (Catalog::gAvailable[d] && Catalog::gMobile[d] && Catalog::gBuilder[d]
				&& Catalog::gFlyer[d] && (!ceiling || ReachesCeiling(d)))
				return true;
		}
	}
	return false;
}

int ConsNeedAny()
{
	const float per = ai.GetTunable("apex_con_per_m", TUNE_CON_PER_M);
	float want = ai.GetTunable("apex_con_base", TUNE_CON_BASE)
			+ ConFloorIncomeTerm(per);
	// METAL WE CANNOT SPEND IS A SHORTAGE OF HANDS, AND THE LINE ABOVE CANNOT
	// SEE IT. It asks what our INCOME implies; the question that decides the
	// game is whether we can spend what we earn. Watched 2026-09-08 on Supreme
	// Isthmus: three constructors held for the whole game while the metal bank
	// sat at 1546 of 1550 and 3,605 metal was thrown away -- and the floor was
	// satisfied, because 2.7 + 33/44 asks for exactly 3 (apexearth: "We're full
	// on metal and our energy is like 1/5th the enemies... we should make more
	// cons in my opinion").
	//
	// The extra hands are derived, not decreed: unspent metal per second is
	// income we are failing to convert, and one constructor converts its own
	// build power's worth per second. So the shortfall in hands is exactly
	// unspent / per-con build power. It reads zero the moment we can spend our
	// income again, which is what makes it a demand and not a cap.
	// ...net of what the hands we have would spend if energy let them: an
	// e-throttled fleet leaves metal unspent without being too few, and more
	// hands add energy draw, not metal spend.
	// ...never by a pure assist unit (apexearth 2026-09-27: unspent metal
	// does not buy Butlers); as constructors only while no lab offers one --
	// a T1 con is also the starter the full bank needed.
	if (!AnyAssistLab())
		want += HandsShort();
	const int have = ConsOwnedAny() + ConsInFlightAny();
	return (float(have) < want) ? (int(want) - have) : 0;
}

// The lathe that is spending right now, at the nominal density: every static
// builder, plus the mobile hands standing at a frame with progress. A hand
// walking to its site, or fleeing a raid, lathes nothing and is not evidence
// of what a hand converts -- counted, the cons a full bank bought raised
// the fleet and not the spend, and the term asked for more (11 cons and no
// army in five minutes).
float gWorkBpVal = 0.f;
float gWorkHandsVal = 0.f;
int gWorkBpAt = -1;
void WorkingLathe()
{
	if (gWorkBpAt == ai.frame)
		return;
	gWorkBpAt = ai.frame;
	float bp = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] > 0) && !Catalog::gMobile[int(d)]
			&& (Catalog::gBuildPower[int(d)] > 0.f))
			bp += float(gOwnCount[d]) * Catalog::gBuildPower[int(d)] * (7.f / 80.f);
	}
	float hands = 0.f;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if ((u is null) || (u.task is null) || (Requests::Progress(u.task) <= 0.01f))
			continue;
		bp += Catalog::gBuildPower[int(u.circuitDef.id)] * (7.f / 80.f);
		hands += 1.f;
	}
	gWorkBpVal = bp;
	gWorkHandsVal = hands;
}

// Constructors short of the income, at the rate the hands we have ACTUALLY
// spend. The nominal density read a T1 con as 7.9 m/s of lathe while three
// of them and the commander spent 17 of 25 between them, so every 8v8 ally
// stood on a full bank for its first six minutes (1.3k metal spilled each,
// BARb's cons 2x ours) with this term at zero. The lab is not the converter
// of that metal either: its line was fed the whole time.
float HandsShort()
{
	TrackIncome();
	const float inc = Eco::MInc();
	const float share = EFeedShare();
	const float spent = (inc - gMSpareEma) / ((share > 0.05f) ? share : 0.05f);
	const float unspent = inc - spent;
	WorkingLathe();
	const float conBp = ConWorkerBP();
	if ((unspent <= 0.f) || (spent <= 0.f) || (gWorkBpVal <= 0.f) || (conBp <= 0.f)
		|| (gWorkHandsVal <= 0.f))
		return 0.f;
	const float short = unspent / (conBp * spent / gWorkBpVal);
	// Bounded by the hands the measurement was taken on.
	return (short < gWorkHandsVal) ? short : gWorkHandsVal;
}

// Does any standing plant of ours offer a pure assist unit?
bool AnyAssistLab()
{
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f !is null) && (AssistDefOf(int(f.circuitDef.id)) >= 0))
			return true;
	}
	return false;
}

// How far under the floor we are. The floor SCALES WITH INCOME -- one con
// plus one per 25 metal/s (apexearth 2026-08-23: "at 100 metal per second we
// should have at least 5"). Any lab qualifies: air, bot or vehicle cons all
// reach the ceiling, and the ReachesCeiling test is def-based, not lab-based.
// A CONSTRUCTOR FLOOR IS BOUNDED BY THE FEED. The income term below is a
// line with no ceiling: at 6,070 m/s it asked for 245 advanced constructors
// (his watch: 150 standing, 234 dead, the advanced air plant a con factory
// for the game and one bomber held of a 299 wing). Hands are lathe, and
// lathe past what the income keeps fed is idle -- so the income term stops
// at the hands the feed has room for: (income x headroom - BPCapacity) over
// one con's own lathe. The unspent-metal term below is the other half of
// the same law and stays.
float ConFloorIncomeTerm(float per)
{
	const float inc = Eco::MInc();
	float term = inc / ((per > 1.f) ? per : 25.f);
	const float hands = inc * ai.GetTunable("apex_con_feed_headroom", TUNE_CON_FEED_HEADROOM);
	// The turrets count against the floor only on the seat, whose ruling is
	// "nanos, not cons". A front player's constructors do what no turret
	// can -- the mohos, the spots -- and counting its turrets read a floor
	// of one advanced con whatever the income.
	const float owned = gEcoRole ? BPCapacity() : MobileBPCapacity();
	const float bp = ConWorkerBP();
	float room = 0.f;
	if ((hands > owned) && (bp > 0.f))
		room = (hands - owned) / bp;
	return (term < room) ? term : room;
}

int CeilingConsNeed()
{
	const float per = ai.GetTunable("apex_t2_con_per_m", TUNE_T2_CON_PER_M);
	float want = ai.GetTunable("apex_t2_con_base", TUNE_T2_CON_BASE)
			+ ConFloorIncomeTerm(per);
	// Unspent metal is hands we lack, at the ceiling tier as at the first:
	// Carrot at 30 min, 9 T2 cons to BARb's 13 and 9 mohos to 18 with 6k
	// metal spilled per game (2026-09-08). ...but it is LATHE we lack, not
	// starters: where a lab offers a pure assist unit the term buys that
	// (apexearth: "If I had 1000 income i would only have 42 T2 cons").
	if (!AnyAssistLab()) {
		const float unspent = UnspentByHands();
		if (unspent > 0.f) {
			const float bp = ConWorkerBP();
			if (bp > 0.f)
				want += unspent / bp;
		}
	}
	const int have = CeilingConsOwned() + CeilingConsInFlight();
	return (float(have) < want) ? (int(want) - have) : 0;
}

// Army metal ORDERED but not yet standing. gOwnCount counts FINISHED units and
// an order takes a whole lag window to become visible, so without this every
// slot of a batch -- and every election inside the lag window -- prices against
// the same gap and buys it over again.
float ArmyInFlightM()
{
	// The metal a queued unit turns into army within the fill window, not its
	// price tag: a Korgoth (29,000) and a Juggernaut (20,000) queued on one
	// gantry read as 49k of army held the instant they were ordered, the
	// ~98k target was met on paper, and every line -- the second gantry
	// included -- cut its whole slate as gap0 for four minutes at 1,000 m/s.
	const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	return Brain::PendArmyMWithin((fillS > 1.f) ? fillS : 180.f);
}

// Why the last ConOrderFor call declined. The facqueue logs it when a line
// comes back with nothing: an election that orders nothing is idle factory
// time, and until this existed the reason was invisible.
string gNoOrder = "";

// The last draw's ranked list, so a line whose election ran out of slice after
// one order can fill the rest of its window from the same distribution
// (measured: every nano'd lab on the seat idle 80% of the game at one order
// per 10 s election, ConOrderFor 16-79 ms a call).
array<int> gRedrawDef;
array<float> gRedrawV;
float gRedrawSum = 0.f;
int gRedrawFac = -1;
int gRedrawAt = -1;

// BUILD POWER IS BOUGHT IN TWO AUCTIONS THAT NEVER COMPETE: the factory buys
// constructors and the want market buys lathes, so a constructor's share of the
// build-power gap has never been priced against the cheaper way to buy the same
// thing. A nano turret is 200 build power for 210 metal; a T2 ground
// constructor is 180 for 430, and it walks to the work and stands on the cell
// we wanted to build on (apexearth 2026-09-23).
float gBestLatheBPM = -1.f;

// THE FASTEST HAND WE CAN FIELD. A lathe delivers its build power from the
// moment it stands; a hand delivers its own only while it is AT the work, and
// a ground constructor moves at 33-36 against an aircraft's 192-208
// (apexearth 2026-09-23: ground hands "are too slow for scaling properly").
// Measured against the quickest builder we own, so it is a ratio the game
// supplies rather than a number chosen here.
float gFastBuilder = -1.f;

float FastestBuilderSpeed()
{
	if (gFastBuilder > 0.f)
		return gFastBuilder;
	float top = 0.f;
	for (uint cd = 1; cd < gOwnCount.length(); ++cd) {
		const int di = int(cd);
		if ((gOwnCount[cd] <= 0) || !Catalog::gMobile[di] || !Catalog::gBuilder[di])
			continue;
		if (Catalog::gSpeed[di] > top)
			top = Catalog::gSpeed[di];
	}
	if (top > 0.f)
		gFastBuilder = top;
	return top;
}

// THE CHEAPEST SOURCE OF A SQUAD SENSOR, over every def any of our builders
// can make. The support need is "a radar per squad", which is one question for
// the fleet -- but it is priced per FACTORY, so a gantry that can only build
// T3 answered it with a 1,250-metal drone carrier while a radar bot costs a
// fraction of that (apexearth, watching: the drone carriers "were 90%
// useless"). A carrier reads as a sensor at all because its weapons are its
// drones, so the unarmed test above passes it.
float gCheapSupM = -1.f;
float gCheapJamM = -1.f;

float CheapestSupportM(bool isJam)
{
	float memo = isJam ? gCheapJamM : gCheapSupM;
	if (memo > 0.f)
		return memo;
	float best = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d] || Catalog::gBuilder[d])
			continue;
		if (Catalog::gSurfT[d] + Catalog::gAirT[d] >= 0.01f)
			continue;
		if (isJam ? !Catalog::gJammer[d] : !Catalog::gRadar[d])
			continue;
		const float m = Catalog::gCostM[d];
		if (m <= 1.f)
			continue;
		if ((best <= 0.f) || (m < best))
			best = m;
	}
	if (best > 0.f) {
		if (isJam)
			gCheapJamM = best;
		else
			gCheapSupM = best;
	}
	return best;
}

float BestLatheBPPerM()
{
	// Never cache a zero: availability is frame-dependent and an early scan
	// would latch the ratio off forever.
	if (gBestLatheBPM > 0.f)
		return gBestLatheBPM;
	float topBPM = 0.f;
	for (int ld = 1; ld <= Catalog::gDefCount; ++ld) {
		if (!Catalog::gAvailable[ld] || !IsLatheDef(ld))
			continue;
		const float lm = Catalog::gCostM[ld];
		if (lm <= 1.f)
			continue;
		const float lr = Catalog::gBuildPower[ld] / lm;
		if (lr > topBPM)
			topBPM = lr;
	}
	if (topBPM > 0.f)
		gBestLatheBPM = topBPM;
	return topBPM;
}

CCircuitDef@ RedrawFor(CCircuitUnit@ fac, int slot)
{
	if ((fac is null) || (gRedrawAt != ai.frame) || (gRedrawFac != int(fac.id))
		|| (gRedrawSum <= 0.f))
		return null;
	uint h = uint(ai.frame) * 2654435761 + uint(fac.id) * 40503
			+ uint(slot) * 2246822519;
	h ^= (h >> 13);
	float roll = float(h % 10000) / 10000.f * gRedrawSum;
	uint pick = 0;
	for (uint ci = 0; ci < gRedrawV.length(); ++ci) {
		roll -= gRedrawV[ci];
		if (roll <= 0.f) {
			pick = ci;
			break;
		}
	}
	if ((FreeMetalFlow() <= 0.5f) && (gWantEmaV > 0.f)
		&& (gRedrawV[pick] < gWantEmaV
			* ai.GetTunable("apex_line_floor", TUNE_LINE_FLOOR)))
		return null;
	// The batch refill skips the draw's checks, so the caps are asked again
	// here: it took a capped fleet to 47/40.
	const int pd = gRedrawDef[pick];
	if (Catalog::gMobile[pd] && Catalog::gBuilder[pd]) {
		if (Catalog::gRezzer[pd] ? (RezFleetHave() >= RezFleetCap())
				: ((ConFleetHave() >= RezFleetCap()) || ConStandsIdle()))
			return null;
	}
	return Catalog::Def(pd);
}

// The line's own ranking, defrank's pattern (his zero-Titan report at
// ~500 m/s: which TERM zeroes a candidate is invisible in every log, and a
// hosted game leaves no infolog to read it from afterwards). One line per
// factory def per minute: every mobile combat candidate with its draw
// weight (v x1000, decide's convention) or the reason it never entered.
array<int> gNextProdRankOf;
int gNextRezLog = 0;

// His ruling 2026-09-26: rez bots stop at max(20, 2% of the lobby's per-player
// maxunits), all rezzer types together, standing plus queued. Not
// GetUnitLimit: BAR's dynamic-maxunits gadget lifts that to ~3,900 in an 8v8.
int gRezCap = -1;
int RezFleetCap()
{
	if (gRezCap < 0) {
		int lim = int(parseInt(string(aiSetupMgr.GetModOptions()["maxunits"])));
		if (lim <= 0)
			lim = 2000;
		gRezCap = (lim / 50 > 20) ? lim / 50 : 20;
	}
	return gRezCap;
}

// Constructors capped like rez bots (apexearth 2026-09-27: "limit those flat
// out the same way we limit rezbots"): a high-bonus economy cannot be spent
// by more hands, and every extra con is lag.
int ConFleetHave()
{
	int n = 0;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if (Catalog::gMobile[di] && Catalog::gBuilder[di] && !Catalog::gRezzer[di]
			&& (Catalog::gCostM[di] > 1.f)
			&& !Catalog::Def(di).IsRoleAny(Unit::Role::COMM.mask))
			n += gOwnCount[d] + Brain::PendAnyOf(di);
	}
	return n;
}

// No new constructor while one we own stands idle (apexearth 2026-09-27:
// "don't make constructors when we aren't even using the ones we have").
bool ConStandsIdle()
{
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ w = gWorkers[i];
		if ((w is null) || (w.circuitDef is null))
			continue;
		const int wd = int(w.circuitDef.id);
		if (!Catalog::gMobile[wd] || Catalog::gRezzer[wd] || (Catalog::gCostM[wd] <= 1.f)
			|| w.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
			continue;
		IUnitTask@ t = w.task;
		if ((t is null) || (t.GetType() == Task::Type::IDLE))
			return true;
	}
	return false;
}

int RezFleetHave()
{
	int n = 0;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if (Catalog::gRezzer[d])
			n += gOwnCount[d] + Brain::PendAnyOf(int(d));
	}
	return n;
}

// `slot` is the position in the line's batch: the facqueue asks repeatedly
// until the queue is deep enough, and every ask is priced against a ledger
// that already carries the slots before it.
// Every mobile radar we own and every mobile jammer, whatever def. The demand
// is a pair per squad; counting per def multiplied it by however many sensor
// types the labs happened to offer.
int gNextAllocLog = 0;
int gSupHaveAt = -1;
float gSupRadarN = 0.f;
float gSupJamN = 0.f;
// The strongest mobile radar/jammer radius in the game -- static def data,
// so caching is safe (availability plays no part in a reference).
float gSupRadarRef = -1.f;
float gSupJamRef = -1.f;

float SupRef(bool jam)
{
	if (jam ? (gSupJamRef > 0.f) : (gSupRadarRef > 0.f))
		return jam ? gSupJamRef : gSupRadarRef;
	float best = 1.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gMobile[d] || Catalog::gBuilder[d])
			continue;
		const float r = jam ? Catalog::gJamR[d] : Catalog::gRadarR[d];
		if (r > best)
			best = r;
	}
	if (jam)
		gSupJamRef = best;
	else
		gSupRadarRef = best;
	return best;
}
void SupportCensus()
{
	if (gSupHaveAt == ai.frame)
		return;
	gSupHaveAt = ai.frame;
	gSupRadarN = 0;
	gSupJamN = 0;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if (!Catalog::gMobile[di] || Catalog::gBuilder[di])
			continue;
		if (!Catalog::gRadar[di] && !Catalog::gJammer[di])
			continue;
		if (Catalog::gSurfT[di] + Catalog::gAirT[di] > 0.01f)
			continue;
		// What we OWN plus what we have already SENT for: gOwnCount only counts
		// finished units, so topping up against it re-orders for the whole walk
		// window.
		// CAPABILITY, NOT WARM BODIES (apexearth: "take one more look at the
		// radar planes - i don't see them still... we lack vision"). A
		// Peeper's 730-elmo set counted as one full radar, so three scouts
		// read the quota as filled and the Oracle's demand priced zero
		// forever. Each unit now counts as its share of the best mobile
		// set's radius.
		const float nHave = float(gOwnCount[d] + Brain::PendAnyOf(di));
		if (Catalog::gRadar[di])
			gSupRadarN += nHave * (Catalog::gRadarR[di] / SupRef(false));
		else
			gSupJamN += nHave * (Catalog::gJamR[di] / SupRef(true));
	}
}

// ARMY DEMAND FROM METAL NOTHING ELSE IS SPENDING (apexearth 2026-09-05: "if
// we're crazy rich and aren't empty on metal then we should just keep making
// army. The objective is to win!"). FreeMetalFlow, not OverflowM: the latter
// reports nothing until the bank passes 80% of storage, and the bank never got
// there because the constructors were spending the same free metal on more
// plants -- so a satisfied target idled every line, gantries included, while
// the auction kept buying lines to stand idle beside them.
float RichArmyGapM()
{
	// gMSpareEma, not the raw tick and not FreeMetalFlow. The raw income-pull
	// "calls a fully committed economy idle one tick and starving the next"
	// (want_energy.as:501), and FreeMetalFlow adds the bank as a 60s drawdown,
	// so a 600-metal bank read as free metal at minute 3 and this floor fired
	// through the whole opening. Both were measured: battery trade mean 0.495
	// control -> 0.446 freeflow -> 0.568 raw-tick, con retreats up on two maps
	// in both. The smoothed spare is the same fact without either error.
	TrackIncome();
	const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	float m = gMSpareEma * ((fillS > 1.f) ? fillS : 180.f);
	// THE OTHER HALF OF THE BALANCE. The budget corrector steers what
	// CONSTRUCTORS build and this file never consults it, so spare metal
	// becomes army whatever the army row says: measured 0.32 held against a
	// 0.202 target while defence sat at 0.142 against 0.288 with its own
	// multiplier railed at the clamp. Amplifying the starved categories
	// cannot work while the overfed one is not on the scale.
	return m;
}


// Spare metal becomes army only while we out-build them (apexearth 2026-09-25,
// Koom 8v8: our army led theirs while they out-earned us 2x). The economy
// signal we have for them is the structure metal we have seen; ours is the
// team's own, summed across allies.
const string TV_ASSETS = "apexAssetsM";
bool gEcoBehind = true;
int gEcoBehindAt = -999999;
bool EcoBehind()
{
	if (ai.frame < gEcoBehindAt + 30 * SECOND)
		return gEcoBehind;
	gEcoBehindAt = ai.frame;
	ai.PublishTeamValue(TV_ASSETS, gAssetsM);
	float ours = 0.f;
	array<Id>@ mates = ai.GetTeamIds();
	for (uint i = 0; (mates !is null) && (i < mates.length()); ++i)
		ours += ai.ReadTeamValue(int(mates[i]), TV_ASSETS, 0.f);
	if (ours < gAssetsM)
		ours = gAssetsM;
	const float theirs = aiEnemyMgr.GetEnemyStructCost();
	gEcoBehind = (theirs >= ours);
	AiLog("apex: ecoside t=" + ai.teamId + " ours=" + int(ours) + " theirs=" + int(theirs)
		+ " behind=" + (gEcoBehind ? 1 : 0));
	return gEcoBehind;
}

CCircuitDef@ ConOrderFor(CCircuitUnit@ fac, int line, int slot)
{
	if (fac is null)
		return null;
	WorthDiag();      // self-gated, once, and only when asked for
	LineClassDiag();  // likewise: the class split, once the field is known
	gNoOrder = "";
	if (int(gNextProdRankOf.length()) <= Catalog::gDefCount)
		gNextProdRankOf.resize(Catalog::gDefCount + 1);
	const int prankUid = int(fac.circuitDef.id);
	const bool prankNow = (ai.frame >= gNextProdRankOf[prankUid]);
	string prank = "";
	// Production pays the E-flow discipline too: a factory pumping pawns
	// through a stall both causes it and starves the opening (watched:
	// hard e-stall, a minute without a mex). But once METAL is overflowing
	// the mute is upside down: the engine already throttles a fed line to
	// the energy actually there, while an emptied queue idles the whole
	// lathe fleet AND stops pulling E, hiding the demand the energy market
	// prices generators against. Stock produces straight through its
	// stalls; muted, we read factory duty 38-45% with 28% of all metal
	// made wasted through the decisive midgame (nanofix-s3). eFeedA below
	// still prices the stall into every army gain.
	if (HardEStall() && (OverflowM() <= 0.5f)) {
		gNoOrder = "e-stall";
		return null;
	}
	// THE ESCORT FLOOR, ahead of everything: a constructor working without a
	// guard is a write-off waiting to happen, and the cheapest answer costs a
	// few seconds of one line. It outranks the all-quiet gate and the
	// in-flight gate below -- like the con floor, this is a rule, not a bid,
	// and it self-limits to the number of unescorted workers.
	// (The escort FLOOR that used to return here is gone -- an escort is now a
	// priced candidate in the loop below, like every other product. A floor
	// cannot be out-ranked however cheap the alternative, which is the shape
	// the plan forbids; the gain is EscortGain and the demand still
	// self-limits to the number of unescorted workers.)
	// The T2-con floor outranks the all-quiet gate: "at least 2" is not
	// contingent on there being other demand.
	const int ceilNeed = CeilingConsNeed();
	// The all-quiet gate and the block below asked the same six questions, and
	// each is a walk of the whole def table -- so every one ran twice per order.
	const float upD = UpDemand();
	const float bpGap = BPGap();
	float armyT0 = ArmyTarget();
	float armyVal0 = ArmyValue();
	{
		const float navyShare = NavyShare();
		if (navyShare > 0.f) {
			if (PlantClass(int(fac.circuitDef.id)) == PC_WATER) {
				armyT0 = ArmyTargetFull() * navyShare;
				armyVal0 = NavyValue();
			} else {
				armyT0 *= 1.f - navyShare;
				armyVal0 -= NavyValue();
				if (armyVal0 < 0.f)
					armyVal0 = 0.f;
			}
		}
	}
	const float armyFlight0 = ArmyInFlightM();
	const float armyHave = armyVal0 + armyFlight0;
	const bool ovfHands = OverflowBuysHands();
	const float richGap = RichArmyGapM();
	const float waterGap = WaterArmyGap(int(fac.circuitDef.id));
	if ((ceilNeed <= 0) && !gMexOpen && (upD <= 0.5f) && (bpGap <= 0.5f)
		&& (armyT0 - armyHave <= 0.5f)
		&& (richGap <= 0.5f) && (waterGap <= 0.5f))
	{
		gNoOrder = "all-quiet";
		return null;
	}
	const int fid = int(fac.circuitDef.id);
	const array<int>@ prods = Catalog::BuildsOf(fid);
	// Each product priced, best value ordered. A constructor's gain: the
	// tier-unique upgrade demand it unlocks, at DIMINISHING returns per con
	// already serving (the binary version stopped at exactly one T2 con);
	// plus its worth as mobile build power (overflow capture at its drain);
	// plus the open-spot stream if ground remains to claim.
	const float util = Utilization();
	const float over = bpGap * util;
	const float mobileCeil = OwnedMobileCeil();
	LossDecay();
	float armyGap = armyT0 - armyHave;
	string gapSrc = "target";
	// COVERAGE IS ARMY DEMAND: the light units the base still needs so a
	// guard stands by every building (military/guardposts.as, his "units
	// are cover" ruling). Not a share of income -- what the base's own
	// spread asks for, and it grows with the base, never with a clock.
	float coverShare = 0.f;   // how much of the gap is coverage, 0..1
	{
		const float coverGap = Military::CoverNeedM() - armyFlight0;
		if (coverGap > armyGap) {
			armyGap = coverGap;
			gapSrc = "cover";
		}
		// COVER IS THE FIRST CLAIM ON THE LAB. A proportional share let a
		// big army target drown the coverage need under the role prior
		// (watched: 13 Pawns to 40 Rocko/Hammer with 30 Pawns of cover
		// unmet all game); apexearth: "the first units out of the factory
		// are the light ones... we still need a lot more light units".
		if ((armyGap > 1.f) && (coverGap > 0.f))
			coverShare = 1.f;
	}
	const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	// METAL WE FAIL TO SPEND IS ARMY DEMAND (his standing law: the economy
	// is for spending; waste is free army) -- see RichArmyGapM for why the
	// signal is free flow and not the storage-gated overflow.
	// ...UNLESS THE TARGET IS ECONOMY, in which case metal we cannot spend is a
	// shortage of HANDS, not of army -- which is the same thing the ladder's
	// max() says when a step is build-bound rather than feed-bound. The
	// constructor gain below already prices overflow capture, so the metal has
	// somewhere to go.
	// The spare-metal floor is the binding term two thirds of the time and the
	// budget cannot see it, so army outruns its share while defence sits under
	// its own with the corrector railed. Offer the spare only as far as army is
	// still owed; the rest stays for the constructor market, which does price
	// against the target.
	float richBal = richGap;
	{
		const float rb = ai.GetTunable("apex_army_rich_balance", TUNE_ARMY_RICH_BALANCE);
		if (rb > 0.f) {
			const float tgt = Brain::TargetShare(Brain::ARMY);
			float owed = (tgt > 0.f) ? (1.f - Brain::ShareOf(Brain::ARMY) / tgt) : 0.f;
			if (owed < 0.f)
				owed = 0.f;
			else if (owed > 1.f)
				owed = 1.f;
			richBal *= (1.f - rb) + rb * owed;
		}
	}
	// Before our own T2 lab stands, spare metal is the T2 lab's, not T1 army
	// (apexearth 2026-09-26: at +100% the T1 window is too short to use).
	if ((TopOwnPlantTier() < 2) || EcoBehind())
		richBal = 0.f;
	if (!ovfHands && (richBal > armyGap)) {
		armyGap = richBal;
		gapSrc = "rich";
	}
	// THE ROLE MEANS IT (apexearth 2026-09-13: the rear specialist "makes no
	// military, focusing on economy"). ArmyTarget reads zero while it grows,
	// but the cover need, the spilled-metal floor and the escort bid all
	// bought army past it -- his watched specialist spent 76k on army against
	// 48k on economy and lost the most metal on its team. While growing, none
	// of those asks; the raid valve (EcoDangerNear) ends the growth instead.
	const bool ecoGrowing = EcoRoleGrowing();
	if (ecoGrowing && (EcoRoleRamp() <= 0.f)) {
		armyGap = 0.f;   // ArmyTarget already carries the ramp past half the target
		coverShare = 0.f;
	}
	// THE BETTER LINES SPEND FIRST. Every factory filled the whole army gap
	// on its own, so a T1 lab kept turning out Hammers at full rate beside a
	// T2 lab against an enemy that was all T2 (Carrot 1v1: 179 T1-lab orders
	// in the last ten minutes at foe tier above1=0.94). This line is left the
	// gap the better lines cannot spend within the fill window at their own
	// build rate -- with one T2 lab that is a few hundred metal, which is what
	// fodder is for; a big gap the T2 lab cannot fill is still T1's to fill.
	// Coverage demand (cheap bodies) is not taken away: the better lines do
	// not make it.
	{
		const float mine = FacBestPPC(fid);
		float betterCap = 0.f;
		for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
			CCircuitUnit@ f2 = Factory::gFacUnits[fi];
			if ((f2 is null) || (f2.circuitDef is null) || (int(f2.id) == int(fac.id)))
				continue;
			const int f2d = int(f2.circuitDef.id);
			if (FacBestPPC(f2d) <= mine)
				continue;
			betterCap += FacMetalRate(f2) * fillS;
		}
		if (betterCap > 0.f) {
			const float coverGapKeep = armyGap * coverShare;
			float left = armyGap - betterCap;
			if (left < coverGapKeep)
				left = coverGapKeep;
			if (left < 0.f)
				left = 0.f;
			// The spare-metal sink re-enters as its own gap per candidate, so it
			// yields too, or a full bank kept every T1 lab running beside T2.
			richBal -= betterCap;
			if (richBal < 0.f)
				richBal = 0.f;
			gYieldLog = " yield=" + int(armyGap - left) + " betterCap=" + int(betterCap)
				+ " richLeft=" + int(richBal);
			armyGap = left;
		} else {
			gYieldLog = "";
		}
	}
	if (waterGap > armyGap) {
		armyGap = waterGap;
		gapSrc = "water";
	}
	// The eco role no longer DISCOUNTS army production -- it removes army from
	// this player's target (ArmyTarget returns 0 while growing), so armyGap is
	// already zero here and a second multiplier would apply the same rule
	// twice. What the role still changes is WHICH unit the late budget buys:
	// the quality bias further down.
	const float roleMul = 1.f;
	// THE STAKE (apexearth 2026-08-23): "all the value we have built up will
	// be lost if we have insufficient army." Under-matched, a unit's worth
	// scales with EVERYTHING we own -- expected loss = total value x defeat
	// probability -- tapering to normal at parity. One modeled weight.
	float stakeMul = 1.f;
	int rezDef = -1, rezHave = 0;
	float rezRestore = 0.f, rezStream = 0.f, rezCap = 0.f, rezEat = 0.f;
	float pLineSum = 0.f;
	int pLineN = 0;
	{
		const float aT0 = armyT0;
		if ((aT0 > 1.f) && (armyGap > 0.f)) {
			// Towers lighten the stake, but only LOCALLY (apexearth): static
			// defense standing in the core counts toward the army at an
			// immobility discount; a remote mex sentry defends its patch,
			// not the base.
			float coreStaticM = 0.f;
			if (gFarmSet) {
				for (uint sd2 = 0; sd2 < gProtUnit[PROT_DEF].length(); ++sd2) {
					if (gProtUnit[PROT_DEF][sd2] is null)
						continue;
					const AIFloat3 sp2 = gProtPos[PROT_DEF][sd2];
					if ((sp2.distance2D(gFarmPos) < 1200.f)
						|| (Base::gAnchorSet && (sp2.distance2D(Base::gAnchor) < 1200.f)))
						coreStaticM += Catalog::gCostM[gProtDefId[PROT_DEF][sd2]];
				}
			}
			const float lightened = armyGap - coreStaticM
					* ai.GetTunable("apex_static_guard", TUNE_STATIC_GUARD);
			const float effGapS = (lightened > 0.f) ? lightened : 0.f;
			const float deficit = effGapS / aT0;
			stakeMul = 1.f + deficit
					* ((gAssetsM + armyVal0) / aT0)
					* ai.GetTunable("apex_stake_weight", TUNE_STAKE_WEIGHT);
			if (stakeMul > 8.f)
				stakeMul = 8.f;
		}
	}
	// BUILD POWER IS A CLOSED LOOP (his standing ruling, unapplied here):
	// a new pair of hands is worth the feed it can get, and the upgrade
	// stream a con unlocks queues behind the same starved feed once the
	// fleet outnumbers what income keeps fed. Measured (his watched loss):
	// armacv v=146 at income 52 m/s -- the line spent 9 of 25 orders on
	// T2 cons while the army was funded at 0.15, and at the end more metal
	// stood in constructors than in living army.
	float feedRoom = 1.f;
	float starterNeed = 0.f;
	{
		// HANDS ARE LATHE, AND A NANO IS A HAND. Counted as constructors
		// against income/drain, the forecast licensed 260 cons at 1,231 m/s
		// and saw no turret at all (his eco seat: "100 advanced land cons...
		// we should use a lot more nano turrets, and a lot less
		// constructors"). BPCapacity is the same fleet in metal/s, turrets
		// at face value and walkers at their measured discount.
		const float hands = Eco::MInc()
				* ai.GetTunable("apex_con_feed_headroom", TUNE_CON_FEED_HEADROOM);
		const float ownedHands = BPCapacity();
		starterNeed = hands;
		// No need is no room -- not full room, which is what the old guard
		// read when the need was under half a hand (measured: starters=0.5
		// room=1.00 on the seat).
		feedRoom = 0.f;
		if ((hands > 0.5f) && (hands > ownedHands))
			feedRoom = (hands - ownedHands) / hands;
		// A PREDICTION THAT THE WASTE REFUTES. The line above forecasts how many
		// lathes the income can keep fed and caps hands there. Overflow is the
		// measurement that says the forecast is wrong: we are throwing metal
		// away WITH the hands we have, so those hands cannot spend it whatever
		// the formula predicts. Measured on the economy-only board -- bank
		// pegged at the storage cap from minute 6, 46.6% of all metal produced
		// wasted by minute 10, and feedRoom holding constructor production at
		// exactly zero on ten builders.
		//
		// Floored at the share of income nothing is spending, so it is
		// self-cancelling: the moment the metal is being spent the floor is zero
		// again and the forecast governs. NOT gated on a full bank -- see
		// SlackFrac. Only while the target is economy; elsewhere the unspent
		// metal already has somewhere to go (the army sink above), which is what
		// hid this.
		// ...whatever the target: with 200 m/s spilling the hands cannot be
		// "already enough" (measured: room=0 against over=67-242 for ten
		// minutes, no constructor bought).
		{
			const float slack = SlackFrac();
			if (feedRoom < slack)
				feedRoom = slack;
		}
	}
	// T1 AIR ARMY ENDS AT T2 (apexearth: "We need to stop making T1 air army
	// when we have T2 available"): armed fliers from a basic air plant price
	// out once our own advanced air plant stands -- the same metal buys the
	// advanced airframe. Builders and unarmed scouts keep flowing.
	bool t1AirMute = false;
	if ((PlantClass(fid) == PC_AIR) && (PlantTier(fid) == 1)) {
		for (uint ad = 1; ad < gOwnCount.length(); ++ad) {
			const int adi = int(ad);
			if ((gOwnCount[ad] <= 0) || Catalog::gMobile[adi]
				|| (Catalog::gBuildsList[adi].length() == 0))
				continue;
			if ((PlantClass(adi) == PC_AIR) && (PlantTier(adi) >= 2)) {
				t1AirMute = true;
				break;
			}
		}
	}
	// Best power-per-cost this line can produce, for normalizing army bids.
	float linePPC = 0.f;
	for (uint i = 0; i < prods.length(); ++i) {
		const int d = prods[i];
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d]
			|| Catalog::gBuilder[d] || (Catalog::gPower[d] <= 1.f)
			|| Catalog::gKamikaze[d])
			continue;
		const float ppc = UnitCore(d);
		if (ppc > linePPC)
			linePPC = ppc;
	}
	// PROPORTIONAL DRAW, not argmax: a persistent 10% price edge under
	// winner-take-all became 29 cons and zero army from a vehicle lab
	// (measured, ladder t001) -- the same lesson the old Brain's roulette
	// carved into project memory. Candidates weight by value.
	array<int> candDef;
	array<float> candV;
	array<float> candGain;
	float sumV = 0.f;
	int best = -1;
	float bestV = 0.f;
	float bestGain = 0.f;
	const double _tProds = Perf::T0();
	// Two fleet counts the candidate loop below used to re-walk the whole def
	// table for, once per candidate. Negative means "not taken yet".
	int landT1 = -1;
	float claimers = -1.f;
	// EVERYTHING BELOW IS THE SAME ANSWER FOR EVERY CANDIDATE. PatrolShort
	// alone walks the whole def table twice and was called twice per
	// candidate; RoleTarget/RoleValue walk it once each per candidate.
	const float tPatrolMiss = PatrolMiss();   // the cover and screen terms saturate on this half alone
	const float tFoeSpeed = FoeSpeedCap();
	const bool ecoRoleOn = EcoRoleActive();
	const bool ecoQuietOn = EcoQuiet();
	const float bestExt = BestExtract();
	const float incA = Eco::MInc();
	const float tLineBite = ai.GetTunable("apex_line_bite", TUNE_LINE_BITE);
	const float tSpeedWorth = ai.GetTunable("apex_speed_worth", TUNE_SPEED_WORTH);
	const float tCoverWorth = ai.GetTunable("apex_cover_worth", TUNE_COVER_WORTH);
	const float tLosWorth = ai.GetTunable("apex_los_worth", TUNE_LOS_WORTH);
	const float tScreenWorth = ai.GetTunable("apex_screen_worth", TUNE_SCREEN_WORTH);
	const float tEcoArmyMinM = ai.GetTunable("apex_eco_army_min_m", TUNE_ECO_ARMY_MIN_M);
	const float tEcoConKeep = ai.GetTunable("apex_eco_con_keep", TUNE_ECO_CON_KEEP);
	const float tRezUtil = ai.GetTunable("apex_rez_util", TUNE_REZ_UTIL);
	const float tSquadM = ai.GetTunable("apex_squad_m", TUNE_SQUAD_M);
	const float tIntelRate = ai.GetTunable("apex_intel_rate", TUNE_INTEL_RATE);
	const float tWaterPct = ai.GetTunable("apex_water_pct", TUNE_WATER_PCT);
	const float uBudget = incA * ai.GetTunable("apex_unit_afford_s", TUNE_UNIT_AFFORD_S);
	// The energy-feed throttle reads two economy scalars and nothing about the
	// candidate at all.
	float eFeedA = 1.f;
	{
		const float eI = Eco::EInc();
		const float eP = Eco::EPull();
		if ((eP > 1.f) && (eI < eP))
			eFeedA = eI / eP;
	}
	// Lazily taken, because the branch that needs each one may never be
	// reached: negative (or -2 for the int) means "not taken yet".
	int escShort = -2;
	float escGain = -1.f;
	float supSquads = -1.f;
	float supAdvArmy = -1.f;
	float floatVal = -1.f;
	int amphBan = -1;
	int consNeedA = -1;
	float bpProt = -1.f;
	// THE ESCORT FLOOR (his ruling 2026-09-22: "force an escort to be produced
	// for each constructor in the early game since we have almost no army").
	// Early = the free army is worth less than the metal walking out alone.
	{
		escShort = EscortShortfall();
		int escD = -1;
		int escFly = 0;
		for (uint i = 0; i < prods.length(); ++i) {
			const int d = prods[i];
			if (!EscortWorthy(d))
				continue;
			escFly += EscortInFlight(Catalog::Def(d));
			// The strongest, not the cheapest: one escort has to win the duel
			// alone, and a Tick loses to the Pawns that kill most of our cons.
			if ((escD < 0) || (Catalog::gPower[d] > Catalog::gPower[escD]))
				escD = d;
		}
		const float atRisk = EscortMetalAtRisk();
		const float freeArmy = RoleValue(int(Unit::Role::RAIDER.type));
		if ((escD >= 0) && (Catalog::gFloater[escD] || Catalog::gSub[escD]))
			escShort = EscortShortfallWet();
		if ((escD >= 0) && (escShort - escFly > 0) && (freeArmy < atRisk)) {
			AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName()
				+ " #" + fac.id + " -> produce:" + Catalog::Def(escD).GetName()
				+ " (escort floor short=" + escShort + " inflight=" + escFly
				+ " risk=" + formatFloat(atRisk, "", 0, 0)
				+ " free=" + formatFloat(freeArmy, "", 0, 0) + ")");
			return Catalog::Def(escD);
		}
	}
	// RoleTarget and RoleValue are per ROLE, and a line offers far more
	// candidates than roles. Linear over at most a handful of entries.
	array<int> rcRole;
	array<float> rcTgt;
	array<float> rcVal;
	const bool metalPath = MetalPathStarved();
	int rezFleet = -1;
	int conFleet = -1;
	int conIdle = -1;
	for (uint i = 0; i < prods.length(); ++i) {
		const int d = prods[i];
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d])
			continue;
		// The def's own cap (behaviour.json "limit"): the Tick's screen axis
		// out-prices every pawn, and its config says five.
		// A screen class counts its recent dead against the limit too: the
		// standing count never reached it while the lab replaced every flea
		// that died at its post.
		// ...and its queued orders, or the cap leaks by the queue depth.
		// Radars and jammers are unarmed too, but not screen: the Ticks' dead
		// filled their cap of two with none standing.
		const int screenDead = ((Catalog::gPower[d] <= 1.01f)
					&& !Catalog::gRadar[d] && !Catalog::gJammer[d])
				? int(Military::ScreenLostM() / ((Catalog::gCostM[d] > 1.f) ? Catalog::gCostM[d] : 1.f))
				: 0;
		if ((Catalog::gLimit[d] > 0) && (Catalog::gLimit[d] < 1000000)
			&& (gOwnCount[d] + Brain::PendAnyOf(d) + screenDead >= Catalog::gLimit[d])) {
			if (prankNow)
				prank += " " + Catalog::Def(d).GetName() + ":limit";
			continue;
		}
		if (Catalog::gRezzer[d]) {
			if (rezFleet < 0)
				rezFleet = RezFleetHave();
			if (rezFleet >= RezFleetCap()) {
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName() + ":rezcap";
				continue;
			}
		} else if (Catalog::gBuilder[d] && Catalog::gMobile[d]) {
			if (conFleet < 0)
				conFleet = ConFleetHave();
			if (conFleet >= RezFleetCap()) {
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName() + ":concap";
				continue;
			}
			if (conIdle < 0)
				conIdle = ConStandsIdle() ? 1 : 0;
			if (conIdle == 1) {
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName() + ":conidle";
				continue;
			}
		}
		if (EcoOnly() && !Catalog::gBuilder[d])
			continue;   // the economy-only benchmark: hands only
		// Metal first: the unlock in flight takes the feed (guards.as).
		// ...except the fleet where our land is cut off: every yard builds
		// fighting ships from the start (his ruling 2026-09-28).
		if (metalPath && !Catalog::gBuilder[d]
			&& !((Catalog::gFloater[d] || Catalog::gSub[d]) && LandLocked())) {
			if (prankNow)
				prank += " " + Catalog::Def(d).GetName() + ":metalpath";
			continue;
		}
		if (t1AirMute && !Catalog::gBuilder[d] && (Catalog::gPower[d] > 1.f))
			continue;
		// THE WING'S LOOK: an air scout bought for what seeing their economy
		// adds to the first bomber's price (Air::LookGainFor). A second demand
		// beside the support one below, not instead of it.
		if (!Catalog::gBuilder[d] && Air::IsLookDef(d)) {
			const float gainL = Air::LookGainFor(d, fillS) * roleMul;
			if (gainL > 0.f) {
				const float vL = gainL / Catalog::gCostM[d];
				candDef.insertLast(d);
				candV.insertLast(vL);
				candGain.insertLast(gainL);
				sumV += vL;
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName()
						+ ":look(v" + formatFloat(vL, "", 0, 3) + ")";
			}
		}
		if (!Catalog::gBuilder[d] && IsLiftDef(d)) {
			const float gainT = LiftGainFor(d, fillS) * roleMul;
			if (gainT > 0.f) {
				const float vT = gainT / Catalog::gCostM[d];
				candDef.insertLast(d);
				candV.insertLast(vT);
				candGain.insertLast(gainT);
				sumV += vT;
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName()
						+ ":lift(v" + formatFloat(vT, "", 0, 3) + ")";
			}
			continue;
		}
		// SUPPORT: mobile eyes and static-cover. One radar and one jammer per
		// squad that can actually take one (apexearth: "we only need up to 2 of
		// these per squad that we have"); attachment is the military layer's,
		// production is ours.
		//
		// AN ARMED UNIT IS ARMY. gRadar/gJammer also flag anything carrying
		// radarDistance > 900 or jam > 100, which is a Commando, a Phantom and
		// a battleship -- priced here they never entered the army market at
		// all, and each one drew its own copy of the demand below.
		// THE FLEET'S OWN EYES AND JAMMER (his 2026-09-28: "put a radar jammer
		// on them"). Where our land is cut off, a ship carrying radar/sonar --
		// armed or not, the Herring is both -- or a jammer is fleet support,
		// sized on our navy, one each per squad of ships.
		const bool navySup = IsNavyDef(d) && Catalog::gMobile[d] && (NavyShare() > 0.f)
				&& ((Catalog::gRadarR[d] > 0.f) || (Catalog::gJamR[d] > 100.f));
		if (Catalog::gMobile[d] && !Catalog::gBuilder[d]
			&& (navySup || ((Catalog::gSurfT[d] + Catalog::gAirT[d] < 0.01f)
				&& (Catalog::gRadar[d] || Catalog::gJammer[d]))))
		{
			SupportCensus();
			const bool isJamS = navySup ? (Catalog::gJamR[d] > 100.f) : !Catalog::gRadar[d];
			const float haveS = navySup ? NavySupportCount(isJamS)
					: (isJamS ? gSupJamN : gSupRadarN);
			// THE DEMAND IS SQUADS, AND IT IS ONE QUESTION PER CLASS.
			// It was AdvArmyValue/squadM asked once per DEF: eight sensor defs
			// each targeting the same fifteen "squads" is a hundred and twenty
			// units, which is what he counted. EscortSquadCount is the live
			// number of groups CSupportTask will actually attach one to.
			const float squadM = tSquadM;
			if (supSquads < 0.f) {
				supSquads = float(int(Military::EscortSquadCount()));
				supAdvArmy = AdvArmyValue();
			}
			const float squads = supSquads;
			float need = supAdvArmy / ((squadM > 1.f) ? squadM : 2000.f);
			if (squads < need)
				need = squads;
			if ((need < 1.f) && (squads >= 1.f))
				need = 1.f;
			if (navySup) {
				const float navyM = NavyValue();
				need = navyM / ((squadM > 1.f) ? squadM : 2000.f);
				if ((need < 1.f) && (navyM > 0.f))
					need = 1.f;
			}
			// One slot, one price: a def that costs many times the cheapest
			// source of the same sensor fills the slot many times worse --
			// among its own kind: a radar bot cannot sail with the fleet.
			if (!navySup
				&& (ai.GetTunable("apex_support_per_metal", TUNE_SUPPORT_PER_METAL) > 0.f)) {
				const float cheapS = CheapestSupportM(isJamS);
				const float mineS = Catalog::gCostM[d];
				if ((cheapS > 0.f) && (mineS > cheapS))
					need *= cheapS / mineS;
			}
			if (ai.frame >= gSupportDiagAt) {
				gSupportDiagAt = ai.frame + 60 * SECOND;
				AiLog("apex: support-diag t=" + ai.teamId + " def="
					+ Catalog::Def(d).GetName()
					+ " cls=" + (isJamS ? "jam" : "radar")
					+ " have=" + formatFloat(haveS, "", 0, 2)
					+ " own=" + gOwnCount[d]
					+ " pend=" + Brain::PendAnyOf(int(d))
					+ " R=" + gSupRadarN + "/J=" + gSupJamN
					+ " need=" + formatFloat(need, "", 0, 2)
					+ " squads=" + int(squads)
					+ " adv=" + formatFloat(supAdvArmy, "", 0, 0));
			}
			if (need <= 0.f)
				continue;
			// WHAT THE NEXT ONE IS WORTH IS THE SQUAD IT FINDS WITHOUT ONE.
			// The old form paid the full shortfall rate below the line and
			// nothing above it, so the tenth bid as hard as the first. Priced
			// per unit on the share of squads still uncovered, it falls with
			// every one bought and reaches zero when every squad has one --
			// not a limit: an escort with no squad to attach to escorts
			// nothing. `need` is the live squad count, so this grows with the
			// army like everything else.
			float uncov = (need - haveS) / need;
			if (uncov > 1.f)
				uncov = 1.f;
			// ...and the candidate EARNS its own share: an Oracle covering
			// three times the ground earns three times the gain, so per
			// cost the real set competes with the scout instead of losing
			// to its price tag.
			const float capW = isJamS
					? (Catalog::gJamR[d] / SupRef(true))
					: (Catalog::gRadarR[d] / SupRef(false));
			const float gainS = (uncov > 0.f)
					? (uncov * squadM * tIntelRate
						/ 60.f * roleMul * capW)
					: 0.f;
			if (gainS > 0.f) {
				const float vS = gainS / Catalog::gCostM[d];
				candDef.insertLast(d);
				candV.insertLast(vS);
				candGain.insertLast(gainS);
				sumV += vS;
			}
			continue;
		}
		// THE ASSASSIN'S WING. The air eco-raid is the one demand the army gap
		// cannot express: these bombers are bought to delete an enemy economy in
		// one pass, not to hold a line. Priced per bomber over the whole raid its
		// type would need, so a type requiring a hundred to survive their AA
		// carries that. Nothing here is a gate -- if the raid does not pay, the
		// gain is zero and the line builds OTHER army. A bomber never falls
		// through to the line pricing: it cannot hold ground, and priced there
		// by power-per-cost it flies alone to the stock attack.
		if (!Catalog::gBuilder[d] && Air::IsBomberDef(d)) {
			const float gainB = ecoGrowing ? 0.f : Air::StrikeGainFor(d, fillS) * roleMul;
			if (gainB > 0.f) {
				// THE SAME CURRENCY AS THE ARMY BID. The army candidate's
				// value below is its demand RATE (gap over the fill window,
				// scaled by relative quality) -- the cost is multiplied in
				// and divided out again. Dividing the strike rate by cost
				// here priced a Phoenix at v=45.8 beside a Brawler at
				// v=58018 (his 8v8: 159 Hawks, 0 bombers), so the wing only
				// ever grew while the army gap was shut.
				const float vB = gainB;
				candDef.insertLast(d);
				candV.insertLast(vB);
				candGain.insertLast(gainB);
				sumV += vB;
			} else if (prankNow) {
				prank += " " + Catalog::Def(d).GetName() + ":wing0";
			}
			continue;
		}
		// ESCORT: a guard for a worker walking outside safe ground. Priced,
		// not decreed -- see EscortGain. Eligibility stays the military hook's
		// (EscortWorthy), because anything else ordered here would be produced
		// and then refuse the duty.
		Market::EscortFieldCensus();
		if (!Catalog::gBuilder[d] && EscortWorthy(d) && !ecoGrowing && !Outgrown(d)) {
			if (escShort < -1)
				escShort = EscortShortfall();
			if (escShort - EscortInFlight(Catalog::Def(d)) > 0) {
				if (escGain < 0.f)
					escGain = EscortGain(fillS);
				const float gainE = escGain * roleMul;
				if (gainE > 0.f) {
					const float vE = gainE / Catalog::gCostM[d];
					candDef.insertLast(d);
					candV.insertLast(vE);
					candGain.insertLast(gainE);
					sumV += vE;
					if (prankNow)
						prank += " " + Catalog::Def(d).GetName()
							+ ":esc(v" + formatFloat(vE, "", 0, 3) + ")";
					// NO `continue`. This bid used to END the def's evaluation,
					// so a cheap fast unit left the army market entirely and --
					// unlike :cut, :eco and :gap0 -- said nothing on its way
					// out. EscortWorthy is cheap-and-fast, which is also the
					// definition of a raider, so this branch was silently
					// settling a question the market exists to settle. Both bids
					// stand as candidates now: a def wanted for two jobs has two
					// demands, and the draw weighs them.
				}
			}
		}
		// ARMY: fill the gap, best power-per-cost first, diminishing per
		// copy owned so the mix diversifies by arithmetic, not by table.
		// Overflowing metal keeps the line running past the target: idle
		// factory time is free, and army beats waste (watched: "way too
		// much idle time on our T1 lab").
		if (!Catalog::gBuilder[d]) {
			// A suicide unit's power is one detonation -- ammunition, not
			// standing army ("we're just making tumbleweeds", watched 8v8).
			// It never enters the army market; a munitions want can price
			// it honestly later if ever wanted.
			if (Catalog::gKamikaze[d])
				continue;
			// REZ BOTS classify as non-builders (empty build list), so they
			// land HERE, not the builder branch -- which is why none were
			// ever made (watched, twice). Their gain: the recoverable loss
			// pool plus a standing medic share of the army -- LESS WHAT THE
			// FLEET ALREADY SERVES. The old 1/(1+0.33N) divisor never
			// saturated: at a big game's pool the cutoff sat at ~48,000
			// bots, and apexearth counted 256 on the field ("theres not 256
			// rezbots worth of work to do"). The demand is a STREAM in
			// metal/s; each standing bot serves its work rate times a
			// utilization share (walking, spread wrecks), and a new bot is
			// worth only the remainder, capped by its own rate -- the fleet
			// sizes itself to the work and stops.
			// Priced after the loop, on the line's own scale (see rezwant);
			// a raw m/s here was 1/1000th of a pawn's ticket.
			if (Catalog::gRezzer[d]) {
				rezDef = d;
				rezHave = (int(d) < int(gOwnCount.length())) ? gOwnCount[d] : 0;
				rezCap = Catalog::gBuildPower[d] * LineMetalPerEffort()
						* tRezUtil;
				rezStream = RezRateM();
				// Only the wrecks its hull can reach (his 09-13 report: land
				// reclaim bought rez subs and no navy).
				if (!Catalog::gAmphib[d] && !Catalog::gFlyer[d]) {
					const float wet = Military::WreckWetShare();
					const bool boat = Catalog::gFloater[d] || Catalog::gSub[d];
					rezStream = gRezRepairRate
							+ gRezWreckRate * (boat ? wet : (1.f - wet));
				}
				float unmet = rezStream - float(rezHave) * rezCap;
				if (unmet > rezCap)
					unmet = rezCap;
				// A fleet losing more than it could ever return is not
				// short of bots: the wrecks are under the enemy's guns.
				if (Military::RezLostRateM() >= float(rezHave + 1) * rezCap)
					unmet = 0.f;
				// ...and the fleet is part of the army, sized to it (his
				// apex_medic_frac); a wreck stream alone bought bots by
				// the hundred.
				const float medic = ai.GetTunable("apex_medic_frac", TUNE_MEDIC_FRAC);
				if ((medic > 0.f)
					&& (float(rezHave) * Catalog::gCostM[d] >= medic * ArmyValue()))
					unmet = 0.f;
				rezEat = (unmet > 0.f) ? unmet : 0.f;
				rezRestore = rezEat * roleMul;
				continue;
			}
		// Until T3-grade units, the quiet rear builds NO army (apexearth);
			// the bar is the cheapest gantry-tier assault (corshiva 1550,
			// read from the defs 2026-07-30). FIGHTERS are the exception
			// once an air lab stands ("we *do* want fighters"): they guard
			// the air-con fleet, sized by the AA target below.
			const bool airGuard = Catalog::gFlyer[d] && (Catalog::gAirT[d] > 0.f);
			if ((roleMul < 1.f) && !airGuard && (Catalog::gCostM[d]
					< tEcoArmyMinM)) {
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName() + ":eco";
				continue;
			}
			// A LOSING TRADE IS NOT A CANDIDATE. The record already discounts
			// a type against its class bar, but a discount on a lab's whole
			// list only reorders the lab's draw; it never removes anything, so
			// the T1 lab kept turning out Hammers at 0.43 metal-for-metal
			// against a T2 field. A type trading under its class bar against
			// what the enemy fields now is dropped outright (apexearth
			// 2026-09-20: "when we see the enemy having Tier 2 units on the
			// field that dominate Tier 1 units ... stop making Tier 1").
			// Fodder and fighters are never judged (RecordRaw reads 1 for
			// them), so spam survives -- the cheap body wastes the same fire.
			// A type we have never lost one of has no trade to lose: a 90-metal
			// scratch read the Juggernaut as 0.9997 and dropped it for a game.
			if ((ai.GetTunable("apex_record_bite", TUNE_RECORD_BITE) > 0.f)
				&& (RecordRaw(d) < 1.f)
				&& (ai.RecordCount(Catalog::Def(d), -1) > 0))
			{
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName() + ":losing";
				continue;
			}
			if (Outgrown(d)) {
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName() + ":outgrown";
				continue;
			}
			const float sinkGap = (ovfHands || ecoGrowing) ? 0.f : (richBal * roleMul);
			const float effGap = (armyGap > sinkGap) ? armyGap : sinkGap;
			if ((effGap <= 0.f) || (Catalog::gPower[d] <= 1.f) || (linePPC <= 0.f)) {
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName() + ":gap0";
				continue;
			}
			// The golden metrics, weighted by exponent (market/worth.as).
			// Carries the by-name worth override, the reach-vs-shield bonus
			// and the reach-answers-reach response with it.
			float ppc = UnitPPC(d);
			const float ppcCore = ppc;   // before the sight, screen and afford terms
			// A WEAPON THAT ONLY FIRES INTO WATER answers what FLOATS.
			// Surf/air threat are the DLL's own read of what a def can hit
			// -- a plain torpedo contributes to neither, so a torpedo
			// bomber's whole arsenal reads zero here while gPower (which
			// UnitPPC prices) still counts it at full value: 118 Cormorants
			// at 400 metal, top of the enemy AA's kill table, on a game
			// whose afloat latch never fired. Dry, there is no target at
			// any price; afloat, its gap is the seen floating value, not
			// the land army gap (ships mostly read as land roles in the
			// enemy census, so seen SUB value is the readable floor -- an
			// undercount, never zero when the threat is real).
			if ((Catalog::gSurfT[d] <= 0.01f) && (Catalog::gAirT[d] <= 0.01f)) {
				// A sub hits anything sitting in the water, not only subs.
				if (floatVal < 0.f) {
					const float subsM = Military::EnemyCostOf(Unit::Role::SUB.type);
					const float armyM = Military::EnemyArmyCost();
					floatVal = Military::EnemyAfloat()
							? (((armyM > subsM) ? armyM : subsM) * AnswerShare()) : 0.f;
					// Where our land is cut off their army has to cross the
					// water, so it is afloat by construction; blind, the navy
					// budget stands in (his: "we are not making any submarines").
					if (NavyShare() > 0.f) {
						float wetM = ((armyM > subsM) ? armyM : subsM) * AnswerShare();
						const float navyM = ArmyTargetFull() * NavyShare();
						if (navyM > wetM)
							wetM = navyM;
						if (wetM > floatVal)
							floatVal = wetM;
					}
				}
				if (floatVal <= 1.f) {
					if (prankNow)
						prank += " " + Catalog::Def(d).GetName() + ":h2o";
					continue;
				}
				if (floatVal < effGap)
					ppc *= floatVal / effGap;
			}
			// x0 ON DRY MAPS (apexearth: "amphib should be x0" -- and a
			// tiny pond flips the engine's water flag, so the bar is real
			// water share of the map, ~15%).
			// JUDGE LAND WORTH, NOT THE FLAG (his ruling after prodrank's
			// first catch: the TITAN carries BAR's amphibious flag and was
			// x0 on every dry map -- zero built at 500 m/s). A unit whose
			// core worth stands at or above the field reference pays for
			// its guns, not its waterline; the x0 keeps zeroing only the
			// dedicated crossers, whose mobility premium drags their
			// per-metal worth below it.
			// AA IS NOT A DEDICATED CROSSER. Its core worth sits below the
			// field reference because UnitCore weighs dps the mean is
			// ground-dominated by, and an AA unit's guns only answer air --
			// so the x0 above caught the ONLY two mobile AA bots we own
			// (armjeth, armaak) on every dry map, all game, however much air
			// was overhead. Measured: `armjeth:amph` / `armaak:amph` on every
			// prodrank line of a 25-minute game that lost energy and mexes to
			// bombers. The rule keeps zeroing crossers; it stops zeroing the
			// answer to the thing crossing overhead.
			const CCircuitDef@ amphDef = Catalog::Def(d);
			const bool amphIsAA = (amphDef !is null)
					&& amphDef.IsRoleAny(Unit::Role::AA.mask);
			if (Catalog::gAmphib[d] && !amphIsAA && (UnitCore(d) < 1.f)) {
				if (amphBan < 0) {
					float lp = aiTerrainMgr.GetLandPercent();
					if (lp <= 1.5f)
						lp *= 100.f;   // scale-proof: fraction or percent
					amphBan = (aiTerrainMgr.IsWaterAVoid()
							|| (lp > 100.f - tWaterPct)) ? 1 : 0;
				}
				if (amphBan > 0) {
					if (prankNow)
						prank += " " + Catalog::Def(d).GetName() + ":amph";
					continue;
				}
			}
			if (ReachDead(d)) {
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName() + ":reach";
				continue;
			}
			ppc *= WaterFightMul(d) * SubImmunityMul(d);
			// The rear specialist buys quality: weight by unit size so the
			// draw lands on the biggest thing the lab offers, not spam that
			// arrives late or never.
			if (ecoRoleOn) {
				float qual = Catalog::gCostM[d] / 1000.f;
				if (qual < 0.1f)
					qual = 0.1f;
				if (qual > 5.f)
					qual = 5.f;
				ppc *= qual;
			}
			// AND THE STANDING COMPOSITION TARGET: tank / middle / reach / dps
			// as shares of army metal, each class worth more per metal the
			// further below its share it is. Proportional, never a veto.
			ppc *= 1.f + tLineBite * LineShortfall(LineClassOf(d));
			// SPEED IS VALUE (apexearth: "they're fast, we need to properly
			// value speed"). A fast unit reaches the fight, catches raiders,
			// and disengages -- none of which shows up in combat-per-metal.
			// Normalised on 100 elmos/s, roughly a T1 bot.
			// Measured against the fastest ground unit the GAME offers, not a
			// flat 100 elmos/s: the bar is what may be raiding us, and we
			// assume they built the fastest thing they could (apexearth).
			ppc *= 1.f + (Catalog::gSpeed[d] / tFoeSpeed) * tSpeedWorth;
			// AND COVERAGE: ground patrolled per metal, worth something only
			// while the fleet is short of the sites it has to watch. This is
			// what buys pawns early -- cheap and fast is the most coverage per
			// metal there is -- and it fades as the fleet fills.
			if (CoverCapable(d))
				// ...on the patrol reading, which the units bought here fill: the
				// posted-guard share never fell (see PatrolMiss) and this term
				// alone bought a plant's worth of Darts every minute.
				ppc *= 1.f + tCoverWorth * CoverPerMetal(d) * tPatrolMiss;
			// THE COVERAGE SHARE OF THE GAP IS PRICED BY COVER, NOT BY COMBAT
			// (apexearth: "quantify the value of grunts when it comes to
			// defending a base from raiders. It is the speed that they have...
			// being able to cover more of the base structures"). Ground
			// covered per metal is speed over cost; the share of the gap that
			// is coverage is priced on that axis outright, the rest as before.
			// ...BUT ONLY FOR A UNIT THAT CAN ACTUALLY HOLD A POST. coverShare is
			// one scalar for the whole election, so every candidate got the
			// coverage axis whether or not it can answer what threatens a
			// building. CoverUnitDef -- the function that decides what the
			// coverage need is DENOMINATED in -- already excludes flyers and
			// anything that cannot fight on the ground, and the need itself is
			// quoted in armfast. The demand model knows a flyer cannot stand a
			// guard post; the pricing model did not, and CoverPerMetal is just
			// speed-over-cost, which an aircraft wins outright.
			//
			// This is the same argument the water case already makes 80 lines
			// up ("A WEAPON THAT ONLY FIRES INTO WATER answers what FLOATS"),
			// one axis over: a Jethro and a Freedom Fighter answer what flies,
			// and the base's raider-coverage gap is not their gap. Measured
			// 2026-09-08: a Freedom Fighter reached p=16515 against the line
			// mean and scored v=357672 where the Banshee beside it scored 3057.
			const float covD = CoverCapable(d) ? coverShare : 0.f;
			if (covD > 0.f)
				ppc *= pow(CoverPerMetal(d), covD);
			// EYES (apexearth: "we tend to lack scouts... need some kind of
			// value requirement on raider style units and scouts"). Sight is
			// what every other sense in this AI is built on -- the danger
			// model, the army target and the commander's engage test all read
			// zero while we are blind (EnemyArmyCost logged 0 for entire
			// games). A unit's LOS is therefore worth something on its own.
			ppc *= 1.f + (Catalog::gLosR[d] / 1000.f) * tLosWorth;
			// A SCOUT IS NOT A BAD SOLDIER. UnitCore prices dps and hp against
			// cost, and on that yardstick a Tick -- 60 hp, 50 dps, 21 metal --
			// scores far below a Pawn, a gap no speed or sight multiplier on
			// top of it can close because they all multiply that same near-zero
			// core. What a screen sells is ground seen and fire drawn, neither
			// of which is combat, so it is priced on its own axis and the unit
			// is worth the BETTER of the two readings (apexearth: "the arm tick
			// is actually a better choice than the pawn -- super high speed,
			// los, and affordability"). Saturates on the same patrol shortfall
			// the coverage term uses, so the screen stops being bought once the
			// ground is watched.
			{
				WorthMeans();
				const float mineM = Catalog::gCostM[d];
				const float kS = tScreenWorth;
				if ((kS > 0.f) && (mineM > 1.f) && (gWMCost > 1.f)
					&& !Catalog::gFlyer[d])
				{
					const float dash = 1.f + Catalog::gSpeed[d] / tFoeSpeed;
					const float screen = kS * (Catalog::gLosR[d] / 1000.f)
							* dash * tPatrolMiss / (mineM / gWMCost);
					if (screen > ppc)
						ppc = screen;
				}
			}
			// AFFORDABLE NOW BEATS STRONG LATER WHILE WE ARE POOR (apexearth:
			// "pawns are good early game when we cannot afford much stronger
			// things"). Seconds of income the unit costs, against the window
			// we are trying to fill the army gap in. Self-cancelling: as
			// income grows the same unit costs fewer seconds and the discount
			// fades, so this is an economy term, never a clock.
			if (incA > 0.1f) {
				const float fieldSec = Catalog::gCostM[d] / incA;
				const float hA = (fillS > 1.f) ? fillS : 60.f;
				ppc *= hA / (hA + fieldSec);
			}
			// MASS FIRST, T3 FROM SURPLUS (his ruling, after 267,850 metal
			// of T3 lost a massing war at 254 m/s): a unit's bid fades as
			// its bill approaches what income makes in apex_unit_afford_s
			// seconds -- the supers' own affordability shape, applied to
			// the unit line. A pawn barely notices; a Juggernaut needs the
			// income that shrugs it off. No tier table: cost is the tier.
			float affM = 1.f;
			{
				const float uBill = Catalog::gCostM[d];
				if ((uBudget > 1.f) && (uBill >= uBudget)) {
					if (prankNow)
						prank += " " + Catalog::Def(d).GetName() + ":aff0";
					continue;
				}
				if (uBudget > 1.f) {
					affM = (uBudget - uBill) / uBudget;
					ppc *= affM;
				}
			}
			const float have = float((int(d) < int(gOwnCount.length()))
					? gOwnCount[d] : 0);
			// The gap is a STREAM the line fills; clamping the gain to one
			// unit's cost made a Pawn bid 0.6 against any gap size and army
			// never outbid a constructor (two straight BARb losses).
			// (eFeedA is hoisted above the loop: the metal-feed throttle is
			// gone, so nothing left in it reads the candidate. A zero bank
			// spending its whole income is PERFECT efficiency, not danger --
			// apexearth: "'out of metal' is simply failing to spend... we need
			// to spend more." Builds at an empty bank slow to income speed by
			// the engine's own physics, which is the correct state.)
			// This unit's role fills its own NEED gap; a saturated role's
			// units price to the floor whatever their power-per-cost.
			const int rIdx = Catalog::gRole[d];
			int rSlot = -1;
			for (uint rq = 0; rq < rcRole.length(); ++rq) {
				if (rcRole[rq] == rIdx) {
					rSlot = int(rq);
					break;
				}
			}
			if (rSlot < 0) {
				rSlot = int(rcRole.length());
				rcRole.insertLast(rIdx);
				rcTgt.insertLast(RoleTarget(rIdx, armyT0));
				rcVal.insertLast(RoleValue(rIdx));
			}
			float rTarget = rcTgt[rSlot];
			float rValue = rcVal[rSlot];
			// The cover half of the AA target is FIGHTER demand: a ground AA
			// unit cannot fly beside a scout (the 23-Crashers-vs-no-air game).
			if (rIdx == int(Unit::Role::AA.type)) {
				// TWO KINDS OF AA ANSWER TWO QUESTIONS. Ground AA defends the
				// ground it stands on; only a fighter denies the airspace and
				// makes the raids stop. Counted as one role, 21,000 metal of
				// mobile AA closed the gap and the fighters were never bought
				// (apexearth: "not making enough anti-air to convince them to
				// stop. We should have fighters").
				const float fShare = ai.GetTunable("apex_aa_fighter_share",
						TUNE_AA_FIGHTER_SHARE);
				const float escort = Air::CoverDemandM();
				if (fShare > 0.f) {
					float airPart = rTarget - escort;
					if (airPart < 0.f)
						airPart = 0.f;
					const float fTgt = airPart * fShare + escort;
					if (Catalog::gFlyer[d]) {
						rTarget = fTgt;
						rValue = Air::FighterMetalHeld();
					} else {
						rTarget -= fTgt;
						rValue -= Air::FighterMetalHeld();
					}
					if (rTarget < 0.f)
						rTarget = 0.f;
					if (rValue < 0.f)
						rValue = 0.f;
				} else if (!Catalog::gFlyer[d]) {
					rTarget -= escort;
				}
			}
			const float rGap = rTarget - rValue;
			// AA answers their air and nothing else: at or over its target it is
			// not bought, whatever its anti-air damage prices it at as army
			// (apexearth 2026-09-26: 105k of AA against 22k of enemy air, 44% of
			// the army, the Archangel ranked a top army unit on air damage).
			if ((rIdx == int(Unit::Role::AA.type)) && (rGap <= 0.f)) {
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName() + ":aafull";
				continue;
			}
			float roleW = (rTarget > 1.f) ? (rGap / rTarget) : 0.f;
			// THE PORTFOLIO FLOOR MUST NOT REVIVE A ROLE THAT IS WORTH NOTHING.
			// It keeps a never-first role from starving, which is right for the
			// combat roles that all carry a baseline share. AA does not: it is a
			// pure counter and RoleTarget refuses it a baseline outright ("it has
			// no value without enemy air"). Floored anyway, a target of exactly
			// zero came back as 0.05 and the draw bought it -- measured
			// 2026-09-07: enemyAirFresh=0 all game, AA target 0, and 1,500 metal
			// of Crashers held, 30% of the army (apexearth, watching: "we've made
			// 23 AA units and have seen 0 enemy air"). A role the model asks for
			// none of gets none.
			if ((rTarget > 1.f) || (ai.GetTunable("apex_role_floor_zero", 1.f) <= 0.f)) {
				if (roleW < 0.05f)
					roleW = 0.05f;   // never exactly zero: portfolio floor
			}
			// The coverage share of the gap is not a composition question: a
			// guard by every building is asked for by the base, whatever
			// role share the army's mix would give that unit.
			// COVERAGE MUST NOT REVIVE A ROLE THE MODEL PRICED AT ZERO.
			//
			// This line ran immediately after the portfolio-floor guard above
			// and overwrote its answer: coverShare is 1.0 whenever the base has
			// unmet guard coverage, so roleW became 1.0 for EVERY candidate,
			// AA included. The floor fix took AA from 0.05 to 0.00 and this took
			// it to 1.00 -- worse than the bug that was fixed.
			//
			// Measured 2026-09-08, one factory two samples apart, with
			// enemyAirFresh=0 and enemyAirRaw=0 on all 48 rolemix lines:
			//   armjeth=0(p10.166,r0.00,a0.92)          <- role model, correct
			//   armjeth=6969.69(g871.21,p80.268,r1.00)  <- coverage overwrote it
			// 42 of 177 production decisions that game were anti-air, 1,730
			// metal of it, against an enemy that never built an aircraft
			// (apexearth: "we have 17 AA and the enemy has no air. I've asked
			// for us to fix this multiple times").
			//
			// Same predicate as the price axis: a unit that cannot hold a post
			// gets no coverage share, and its role model answer stands.
			const float covR = CoverCapable(d) ? coverShare : 0.f;
			roleW = covR + (1.f - covR) * roleW;
			float gainA = (effGap / ((fillS > 1.f) ? fillS : 60.f))
					* (ppc / linePPC) * roleW * stakeMul
					/ (1.f + have * 0.05f) * eFeedA;
			// The quiet rear's fighters ignore the suppressed army gap and
			// price straight off their own AA gap -- the air census is not
			// role-suppressed, so the guard fleet tracks REAL enemy air.
			if ((roleMul < 1.f) && airGuard) {
				gainA = ((rGap > 0.f) ? rGap : 0.f)
						/ ((fillS > 1.f) ? fillS : 60.f)
						* (ppc / linePPC) / (1.f + have * 0.05f) * eFeedA;
			}
			if (gainA <= 0.01f) {
				if (prankNow)
					prank += " " + Catalog::Def(d).GetName()
						+ "=0(p" + formatFloat(ppc / linePPC, "", 0, 3)
						+ ",r" + formatFloat(roleW, "", 0, 2)
						+ ",a" + formatFloat(affM, "", 0, 2) + ")";
				continue;
			}
			// COST WAS DIVIDED OUT TWICE, AND IT MADE EVERY EXPENSIVE UNIT
			// UNBUYABLE.
			//
			// `ppc` is UnitPPC -- power PER COST -- so `gainA` above is already
			// a per-metal quantity. Dividing it by cost again makes the score
			// proportional to power / cost^2, and a unit is then punished by the
			// SQUARE of its price. Measured 2026-09-08 off the army rank line in
			// 20260907-203921, from a standing T2 bot lab with Fatboy available:
			//
			//   armamph (Platypus, 260m)  g=867.87  ->  867.87/260  = 3.338
			//   armfboy (Fatboy,  1400m)  g= 44.01  ->   44.01/1400 = 0.031
			//
			// Fatboy last of nine, at 1/106th the Platypus. The cost ratio alone
			// (1400/260)^2 is 29x of that before any question of which unit is
			// actually better. apexearth, watching: "we could have made a fatboy
			// easily and kicked the enemies butt but we made like 1 hound, then
			// a fuckin platypus which is USELESS here."
			//
			// `v = gain / cost` is the right shape and every other want kind
			// uses it, so the half that is wrong is the GAIN: it must be the
			// absolute power this unit adds, not power per metal. Multiplying by
			// cost here restores that -- vA then comes out proportional to
			// ppc, which is value per metal, exactly once. This also makes
			// candGain comparable with the other kinds' absolute gains, which it
			// was not before.
			gainA *= Catalog::gCostM[d];
			const float vA = gainA / Catalog::gCostM[d];
			candDef.insertLast(d);
			candV.insertLast(vA);
			candGain.insertLast(gainA);
			sumV += vA;
			// The medic is priced against the line's SOLDIERS, not against
			// their sight and screen premiums: on the final ratio a rez bot
			// read 26 soldiers' worth at minute one with no wreck on the map.
			pLineSum += ppcCore / linePPC;
			++pLineN;
			if (prankNow)
				prank += " " + Catalog::Def(d).GetName()
					+ "=" + formatFloat(vA * 1000.f, "", 0, 2)
					+ "(g" + formatFloat(gainA, "", 0, 2)
					+ ",p" + formatFloat(ppc / linePPC, "", 0, 3)
					+ ",pc" + formatFloat(ppcCore / linePPC, "", 0, 3)
					+ ",r" + formatFloat(roleW, "", 0, 2)
					+ ",a" + formatFloat(affM, "", 0, 2) + ")";
			continue;
		}
		// An ARMED producible builder is a decoy-class unit: it pays for a
		// gun and a disguise nobody asked for (apexearth: "do not want
		// them; maybe useful for later logic").
		if (Catalog::gSurfT[d] + Catalog::gAirT[d] > 0.01f)
			continue;
		if (prankNow)
			prank += " " + Catalog::Def(d).GetName() + ":b";
		float gain = 0.f;
		float reach = 0.f;
		const array<int>@ pb = Catalog::gBuildsList[d];
		for (uint q = 0; q < pb.length(); ++q) {
			if (Catalog::gExtractsM[pb[q]] > reach)
				reach = Catalog::gExtractsM[pb[q]];
		}
		// THE T2 CON FLOOR. Under it this is not an auction: the line
		// orders one now, ahead of the proportional draw and the
		// opportunity floor below. A ceiling con priced against army
		// loses whenever the army gap is open, and the stake multiplier
		// keeps it open -- so the floor is a rule, not a bid. The
		// hard-e-stall and in-flight gates above still hold.
		// THE PLAIN CONSTRUCTOR FLOOR, ahead of the proportional draw for the
		// same reason the T2 one is: a con priced against army loses whenever
		// the army gap is open, and the symmetric prior keeps it open by
		// construction. Any tier counts -- this asks for hands, not reach.
		if (consNeedA < 0)
			consNeedA = ConsNeedAny();
		// A walker yields the floor to a flyer another plant can make.
		const bool walker = !Catalog::gFlyer[d];
		if ((consNeedA > 0) && walker && FlyingConLab(false))
			consNeedA = 0;
		// THE T1 AIR CON FLOOR (his ruling 2026-09-15): once an air lab
		// stands, keep making basic air cons until ten fly -- they are the
		// hands that raise nano turrets -- but never the whole lab: one in
		// the queue at a time, so the other air keeps coming.
		if (!walker && !ReachesCeiling(d) && (T1AirConsNeed() > 0)
			&& (T1AirConsInFlight() == 0))
		{
			AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName()
				+ " #" + fac.id + " -> produce:" + Catalog::Def(d).GetName()
				+ " (t1-air-con floor need=" + T1AirConsNeed()
				+ " have=" + T1AirConsOwned() + ")");
			return Catalog::Def(d);
		}
		if (consNeedA > 0) {
			AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName()
				+ " #" + fac.id + " -> produce:" + Catalog::Def(d).GetName()
				+ " (con floor need=" + consNeedA
				+ " have=" + ConsOwnedAny()
				+ " inflight=" + ConsInFlightAny()
				+ " inc=" + formatFloat(Eco::MInc(), "", 0, 1)
				+ " short=" + formatFloat(HandsShort(), "", 0, 1)
				+ " hands=" + formatFloat(EtaHandsShare(), "", 0, 2) + ")");
			return Catalog::Def(d);
		}
		if ((ceilNeed > 0) && ReachesCeiling(d) && !(walker && FlyingConLab(true))) {
			AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName()
				+ " #" + fac.id + " -> produce:" + Catalog::Def(d).GetName()
				+ " (t2-con floor need=" + ceilNeed
				+ " have=" + CeilingConsOwned()
				+ " inflight=" + CeilingConsInFlight()
				+ " inc=" + formatFloat(Eco::MInc(), "", 0, 1) + ")");
			return Catalog::Def(d);
		}
		// The quiet rear caps LAND con production at its keep-fleet (+2 for
		// attrition): the bank-driven BP gap must buy nanos and air cons,
		// not a walking crowd the reclaimer eats back (watched churn; conT1
		// hit 24 at 15m on the bank term).
		if (ecoQuietOn && !Catalog::gFlyer[d] && (reach < bestExt)) {
			// Nothing in this walk depends on the candidate `d`, and it sat
			// inside the candidate loop -- 949 slots per candidate. Taken at
			// most once per pass, on first use, so the count is the same.
			if (landT1 < 0) {
				landT1 = 0;
				for (uint lc = 1; lc < gOwnCount.length(); ++lc) {
					if ((gOwnCount[lc] > 0) && Catalog::gMobile[int(lc)]
						&& Catalog::gBuilder[int(lc)] && !Catalog::gFlyer[int(lc)]) {
						if (!ReachesCeiling(int(lc)))
							landT1 += gOwnCount[lc];
					}
				}
			}
			if (float(landT1) >= tEcoConKeep + 2.f) {
				if (prankNow)
					prank += "keep";
				continue;
			}
		}
		// A pure assist unit is not bought for claims or unspent metal: its
		// claim term was never netted and it is the cheapest fast claimer, so
		// 53 Butlers walked to far mexes in one game (apexearth 2026-09-27).
		if (IsAssistDef(d)) {
			if (prankNow)
				prank += " " + Catalog::Def(d).GetName() + ":assistfloor";
			continue;
		}
		// >= the game ceiling, not > our own: requiring the next con to
		// EXCEED what the first one reaches made a second armack impossible
		// (measured: one T2 con per game, forever).
		const float mob = MobilityMult(d);
		// A rezzer that also BUILDS lands here instead of the non-builder
		// branch above, and must price off the same stream and the same
		// per-bot rate: build power is not metal/s, so it can be neither
		// subtracted from a metal/s stream nor added to `gain`.
		if (Catalog::gRezzer[d]) {
			const int haveRez = (int(d) < int(gOwnCount.length())) ? gOwnCount[d] : 0;
			const float perBotB = Catalog::gBuildPower[d] * LineMetalPerEffort()
					* tRezUtil;
			float unmetB = RezRateM() - float(haveRez) * perBotB;
			if (unmetB > perBotB)
				unmetB = perBotB;
			if (unmetB > 0.f)
				gain += unmetB;
		}
		if ((upD > 0.5f) && (reach >= bestExt)) {
			// The upgrade stream divides among cons who can REACH it -- a
			// T1 fleet cannot moho anything, so the first T2 con serves
			// the whole 4x stream alone and prices like it (apexearth,
			// watching: "we make a T2 lab but don't even make a T2 con to
			// start off"). Dividing by ServingCons counted busy T1 hands
			// against demand only a T2 con can touch.
			const int ceilCons = CeilingConsOwned();
			gain += mob * upD / float(1 + ceilCons);
		}
		const float drain = Catalog::gBuildPower[d] * (7.f / 80.f);
		float capG = mob * ((over < drain) ? over : drain);
		{
			const float bpm = ai.GetTunable("apex_bp_vs_lathe", TUNE_BP_VS_LATHE);
			const float myM = Catalog::gCostM[d];
			if ((bpm > 0.f) && (myM > 1.f)) {
				const float latheBPM = BestLatheBPPerM();
				float myBP = Catalog::gBuildPower[d];
				if (ai.GetTunable("apex_bp_travel", TUNE_BP_TRAVEL) > 0.f) {
					const float topS = FastestBuilderSpeed();
					const float myS = Catalog::gSpeed[d];
					if ((topS > 0.f) && (myS > 0.f) && (myS < topS))
						myBP *= myS / topS;
				}
				const float myBPM = myBP / myM;
				if ((latheBPM > 0.f) && (myBPM < latheBPM))
					capG *= (1.f - bpm) + bpm * (myBPM / latheBPM);
			}
		}
		gain += capG;
		float claimGain = 0.f;
		if (gMexOpen && (reach > 0.f)) {
			// A con claims spot after spot -- a stream of STREAMS -- but the
			// STREAMS ARE FINITE: 37 cons once chased 13 spots and easy BARb
			// walked over an armyless base (measured, ladder game 1). The
			// claim gain divides by claimers per open spot -- the unserved-
			// demand law, fourth application.
			CacheSpots();
			const float open = float(ClaimableSpots());
			// Loop-invariant: the claimer fleet does not depend on which unit
			// the line is pricing. Taken once per pass on first use.
			if (claimers < 0.f) {
				claimers = 0.f;
				for (uint cd2 = 1; cd2 < gOwnCount.length(); ++cd2) {
					if ((gOwnCount[cd2] > 0) && Catalog::gMobile[int(cd2)]
						&& Catalog::gBuilder[int(cd2)])
						claimers += float(gOwnCount[cd2]);
				}
			}
			float share = (open > 0.f) ? (open / (claimers + 1.f)) : 0.f;
			if (share > 1.f)
				share = 1.f;
			// Over the payback horizon every other economic buy is amortised
			// on: a claimed spot streams for the game, not for one fill window.
			const float hClaim = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
			claimGain = mob * util * SpotM() * (((hClaim > 1.f) ? hClaim : 900.f) / 60.f)
					* share;
		}
		// UNPROTECTED BUILD POWER IS DISCOUNTED BUILD POWER (apexearth: "we
		// are currently walking our constructors out alone and they die...
		// a con outside of our home safe territory immediately has 0 value").
		// Buying another pair of hands to send out unescorted buys less than
		// it costs, so what a new con is worth scales with the share of the
		// build power we already have that is actually protected. It lifts by
		// itself the moment escorts exist -- and the escort want is priced on
		// the same metal (EscortMetalAtRisk), so the two trade against each
		// other honestly instead of both being flat.
		if (bpProt < 0.f)
			bpProt = BPProtectedFrac();
		gain *= bpProt;
		// Rez bots eat the field, not the feed; every other builder pays
		// the closed-loop room for its LATHE. Not for its claims: a mex
		// creates the income the room says is missing, and gated on the
		// room the claim value read zero all game once a few turrets stood
		// (5 constructors to their 16, mexes 3-4 to their 11 at minute 12).
		if (!Catalog::gRezzer[d])
			gain *= feedRoom;
		gain += claimGain * bpProt;
		if (gain <= 0.5f) {
			// A cut candidate leaves no trace otherwise -- it is absent from
			// prodrank, so "we stopped making pawns" reads as a lost election
			// rather than a unit that was never offered.
			if (prankNow)
				prank += " " + Catalog::Def(d).GetName()
					+ ":cut(g" + formatFloat(gain, "", 0, 3)
					+ (Catalog::gBuilder[d] ? (" prot=" + formatFloat(bpProt, "", 0, 2)
						+ " room=" + formatFloat(feedRoom, "", 0, 2)
						+ " claim=" + formatFloat(claimGain, "", 0, 1)
						+ " over=" + formatFloat(over, "", 0, 1)
						+ " open=" + (gMexOpen ? 1 : 0)
						+ " upD=" + formatFloat(upD, "", 0, 1)) : "") + ")";
			continue;
		}
		const float v = gain / Catalog::gCostM[d];
		if (prankNow)
			prank += "=" + formatFloat(v * 1000.f, "", 0, 2) + "(g" + formatFloat(gain, "", 0, 2)
				+ ",claim" + formatFloat(claimGain, "", 0, 1) + ",room" + formatFloat(feedRoom, "", 0, 2) + ")";
		candDef.insertLast(d);
		candV.insertLast(v);
		candGain.insertLast(gain);
		sumV += v;
	}
	if (rezDef >= 0) {
		const float pLine = (pLineN > 0) ? (pLineSum / float(pLineN)) : 1.f;
		const float hM = (fillS > 1.f) ? fillS : 60.f;
		const float pMedic = rezRestore * hM / Catalog::gCostM[rezDef] * pLine;
		// Times cost like gainA above: pMedic is already per metal, and
		// without it the medic was divided by its price twice (v=6974 against
		// a pawn's 350276 at 36 m/s of wrecks and repair, 0 bots standing).
		float gainM = ((armyGap > 0.f) ? armyGap : 0.f) / hM * pMedic * stakeMul
				* eFeedA * Catalog::gCostM[rezDef];
		// THE WRECKS AND THE RETIRED BUILDINGS ARE A STREAM WHATEVER THE
		// ARMY: the medic form above is zero wherever the army target is
		// (the eco seat), and the seat is where old solars and converters
		// pile up (apexearth 2026-09-14: "I think it should be okay for them
		// to [make rezbots]"). The unmet stream, in the con's own m/s
		// currency, stands on its own.
		// ...over the payback horizon, as the constructor's claim is: raw
		// m/s read v=25 against a pawn's 3,240 with 839 m/s of wrecks on the
		// field and fourteen bots standing (his watch: "we are lacking
		// rezbots").
		const float hRez = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
		if (rezEat * eFeedA * ((hRez > 1.f) ? hRez : 900.f) > gainM)
			gainM = rezEat * eFeedA * ((hRez > 1.f) ? hRez : 900.f);
		const float vM = gainM / Catalog::gCostM[rezDef];
		if (gainM > 0.01f) {
			candDef.insertLast(rezDef);
			candV.insertLast(vM);
			candGain.insertLast(gainM);
			sumV += vM;
		}
		if (prankNow)
			prank += " " + Catalog::Def(rezDef).GetName() + "="
				+ formatFloat(vM * 1000.f, "", 0, 2) + "(rez g"
				+ formatFloat(gainM, "", 0, 2) + ")";
		if (ai.frame >= gNextRezLog) {
			gNextRezLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: rezwant t=" + ai.teamId
				+ " stream=" + formatFloat(rezStream, "", 0, 2)
				+ " cap=" + formatFloat(rezCap, "", 0, 2)
				+ " have=" + rezHave
				+ " fleet=" + RezFleetHave() + "/" + RezFleetCap()
				+ " restore=" + formatFloat(rezRestore, "", 0, 2)
				+ " pLine=" + formatFloat(pLine, "", 0, 1)
				+ " pMedic=" + formatFloat(pMedic, "", 0, 1)
				+ " cov=" + formatFloat(coverShare, "", 0, 2)
					+ " gap=" + int(armyGap)
				+ " repairPs=" + formatFloat(gRezRepairRate, "", 0, 2)
				+ " wreckPs=" + formatFloat(gRezWreckRate, "", 0, 2)
				+ " v=" + formatFloat(vM * 1000.f, "", 0, 2)
				+ " sumV=" + formatFloat(sumV * 1000.f, "", 0, 0));
		}
	}
	Perf::Add("prod.cands", _tProds);
	if (prankNow && (prank.length() > 0)) {
		gNextProdRankOf[prankUid] = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: prodrank fac=" + fac.circuitDef.GetName()
			+ " t=" + ai.teamId
			+ " inc=" + formatFloat(Eco::MInc(), "", 0, 0)
			+ " gap=" + int(armyGap) + " src=" + gapSrc + " wgap=" + int(waterGap) + " aT=" + int(armyT0) + " aV=" + int(armyVal0) + " ll=" + (LandLocked() ? 1 : 0)
			+ " flight=" + int(armyFlight0)
			+ " cons=" + ConFleetHave() + "/" + RezFleetCap()
			+ " n=" + candDef.length() + gYieldLog + prank);
	}
	if ((candDef.length() == 0) || (sumV <= 0.f)) {
		gNoOrder = "no-candidate";
		return null;
	}
	// MACRO DECIDES THE MIX, MICRO PICKS THE UNIT.
	//
	// The composition target was a NUDGE on each candidate's price
	// (`apex_line_bite` x LineShortfall). Five separate attempts to make reach
	// reach its share that way all failed -- apex_range_worth, a ShieldShare
	// unwind, a range-scaled hp exponent, a standoff-exposure discount, and the
	// tier fade -- and the metal-weighted reach share never left 0.04-0.07
	// against a target of 0.35. It cannot work: the per-metal spread between a
	// Sheldon (0.16 dps/metal) and a Termite (0.61) is about twelvefold, and a
	// multiplier that also touches the competition can only buy more of
	// everything.
	//
	// A SHARE IS PRODUCED BY ALLOCATING, NOT BY WEIGHTING. So the class the
	// team owes the most metal to is chosen first, and the draw runs among that
	// class's candidates. Same shape as the two changes that DID work today:
	// the reactor slot going to the best member rather than the first asker,
	// and the defence auction ranking the team's catalogue rather than one
	// constructor's. Both worked by changing what is being chosen BETWEEN.
	//
	// Non-combat candidates (constructors, rez bots) are never filtered out --
	// they are not part of the composition and starving them would stop the
	// economy. And when no class is owed anything, or this factory builds none
	// of the owed class, the whole list stands.
	if (ai.GetTunable("apex_line_alloc", TUNE_LINE_ALLOC) > 0.f) {
		TrackLine();
		float lineTot = 0.f;
		for (int lc = 0; lc < LC_N; ++lc)
			lineTot += gLineM[lc];
		int owedCls = -1;
		float owedM = 0.f;
		for (int lc2 = 0; lc2 < LC_N; ++lc2) {
			const float owe = LineTarget(lc2) * lineTot - gLineM[lc2];
			if (owe > owedM) {
				owedM = owe;
				owedCls = lc2;
			}
		}
		if (owedCls >= 0) {
			array<int> aDef;
			array<float> aV;
			array<float> aG;
			float aSum = 0.f;
			bool anyCombat = false;
			for (uint ai2 = 0; ai2 < candDef.length(); ++ai2) {
				const int cd = candDef[ai2];
				const bool combat = LineCombat(cd);
				if (combat && (LineClassOf(cd) != owedCls))
					continue;
				if (combat)
					anyCombat = true;
				aDef.insertLast(cd);
				aV.insertLast(candV[ai2]);
				aG.insertLast(candGain[ai2]);
				aSum += candV[ai2];
			}
			// Only take the filtered list if it still offers a combat unit --
			// otherwise this factory cannot serve the owed class and keeps its
			// full list rather than being reduced to constructors.
			// BOTH BRANCHES LOGGED. A line that only prints when the filter
			// APPLIES cannot tell "never ran" from "ran and this factory
			// cannot serve the owed class" -- the same blindness the gate
			// census exists to remove, reintroduced here on the first try.
			const bool applied = anyCombat && (aSum > 0.f);
			// THE LAB THAT CANNOT SERVE THE DEBT STANDS DOWN -- but only if
			// something else can serve it. apexearth's ruling, 2026-08-30: "If
			// T2 is available then perhaps the T1 lab does nothing. If T2 is
			// not available then the T1 lab does the best it can." Without the
			// second half this idles the whole economy on a map where nobody
			// has teched; with it, a T1 lab keeps working right up until the
			// advanced plant that can pay the debt exists.
			//
			// The debt must be worth at least one purchasable unit of the owed
			// class before anyone stands down -- an 18-metal shortfall is not a
			// reason to idle a factory. That bar is the cheapest member our own
			// plants can build, so it is read off the unit table rather than
			// chosen.
			bool yield = false;
			if (!applied) {
				const float cheapest = ClassCheapestOwned(owedCls);
				yield = (cheapest > 0.f) && (owedM >= cheapest);
			}
			if (ai.frame >= gNextAllocLog) {
				gNextAllocLog = ai.frame + 30 * SECOND;
				AiLog(Factory::T() + "apex: linealloc t=" + ai.teamId
					+ " fac=" + fac.circuitDef.GetName()
					+ " owed=" + LineClassName(owedCls)
					+ " byM=" + int(owedM)
					+ " armyM=" + int(lineTot)
					+ (applied
						? (" APPLIED cand=" + candDef.length() + "->" + aDef.length())
						: (yield
							? (" YIELD (a plant that can serve it stands; cheapest="
								+ int(ClassCheapestOwned(owedCls)) + ")")
							: " CANNOT-SERVE, no plant can either -- best effort")));
			}
			if (yield) {
				gNoOrder = "line-alloc-yield";
				return null;
			}
			if (applied) {
				candDef = aDef;
				candV = aV;
				candGain = aG;
				sumV = aSum;
			}
		}
	}
	// Deterministic weighted pick: seeded from frame+line so replays hold.
	uint h = uint(ai.frame) * 2654435761 + uint(fac.id) * 40503
			+ uint(slot) * 2246822519;
	h ^= (h >> 13);
	float roll = float(h % 10000) / 10000.f * sumV;
	uint pick = 0;
	for (uint ci = 0; ci < candV.length(); ++ci) {
		roll -= candV[ci];
		if (roll <= 0.f) {
			pick = ci;
			break;
		}
	}
	best = candDef[pick];
	bestV = candV[pick];
	bestGain = candGain[pick];
	gRedrawDef = candDef;
	gRedrawV = candV;
	gRedrawSum = sumV;
	gRedrawFac = int(fac.id);
	gRedrawAt = ai.frame;
	// Priced in the same currency; factory time is free while the line idles.
	// OPPORTUNITY FLOOR: the draw compares a line's candidates only against
	// each other, so a saturated line kept producing v=1.2 cons while
	// fusion money earned v=30+ outside (measured: 22 armacks, 1 fusion).
	// The floor is a SCARCITY question, gated on FreeMetalFlow: with
	// unspent flow standing, an idle line is pure waste whatever the EMA
	// says. The old OverflowM gate (bank at 80% storage) opened far too
	// late, and the per-metal EMA compare structurally idled every
	// expensive T2 line meanwhile (A/B, seed 5: 1 produce decide in 5.5
	// minutes at floor 0.25 vs a real stream at 0). In true scarcity the
	// per-metal compare is right -- metal IS the constraint there.
	if ((FreeMetalFlow() <= 0.5f) && (gWantEmaV > 0.f)
		&& (bestV < gWantEmaV
			* ai.GetTunable("apex_line_floor", TUNE_LINE_FLOOR))) {
		gNoOrder = "line-floor v=" + formatFloat(bestV * 1000.f, "", 0, 2)
				+ " ema=" + formatFloat(gWantEmaV * 1000.f, "", 0, 2);
		return null;
	}
	AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName() + " #" + fac.id
		+ " -> produce:" + Catalog::Def(best).GetName()
		+ " v=" + formatFloat(bestV * 1000.f, "", 0, 2)
		+ " (gain=" + formatFloat(bestGain, "", 0, 2)
		+ " m=" + formatFloat(Catalog::gCostM[best], "", 0, 0)
		+ " serving=" + ServingCons()
		+ " hands=" + formatFloat(EtaHandsShare(), "", 0, 2)
		+ " lathe=" + formatFloat(starterNeed, "", 0, 0) + "/" + formatFloat(BPCapacity(), "", 0, 0)
		+ " room=" + formatFloat(feedRoom, "", 0, 2) + ")");
	return Catalog::Def(best);
}


}  // namespace Market
