namespace Market {
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
	int n = 0;
	for (uint c = 1; c < gOwnCount.length(); ++c) {
		if ((gOwnCount[c] <= 0) || !Catalog::gMobile[int(c)]
			|| !Catalog::gBuilder[int(c)]
			|| Catalog::Def(int(c)).IsRoleAny(Unit::Role::COMM.mask))
			continue;
		if (ReachesCeiling(int(c)))
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
	int n = 0;
	for (uint i = 0; i < Brain::gFQPendDef.length(); ++i) {
		CCircuitDef@ pd = Brain::gFQPendDef[i];
		if ((pd !is null) && ReachesCeiling(int(pd.id)))
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
int ConsOwnedAny()
{
	int n = 0;
	for (uint c = 1; c < gOwnCount.length(); ++c) {
		if ((gOwnCount[c] <= 0) || !Catalog::gMobile[int(c)]
			|| !Catalog::gBuilder[int(c)]
			|| Catalog::Def(int(c)).IsRoleAny(Unit::Role::COMM.mask))
			continue;
		n += gOwnCount[c];
	}
	return n;
}

// Ordered but not standing. gOwnCount counts FINISHED units, and an order is
// not applied on the frame it is issued, so without this the floor re-orders
// for the whole build and lands a crowd.
int ConsInFlightAny()
{
	int n = 0;
	for (uint i = 0; i < Brain::gFQPendDef.length(); ++i) {
		CCircuitDef@ pd = Brain::gFQPendDef[i];
		if ((pd !is null) && pd.IsMobile() && pd.IsBuilder()
			&& !pd.IsRoleAny(Unit::Role::COMM.mask))
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
	const float pull = aiEconomyMgr.metal.pull / ((share > 0.05f) ? share : 0.05f);
	return aiEconomyMgr.metal.income - pull;
}

int ConsNeedAny()
{
	const float per = ai.GetTunable("apex_con_per_m", TUNE_CON_PER_M);
	float want = ai.GetTunable("apex_con_base", TUNE_CON_BASE)
			+ aiEconomyMgr.metal.income / ((per > 1.f) ? per : 44.f);
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
	const float unspent = UnspentByHands();
	if (unspent > 0.f) {
		const float bp = ConWorkerBP();
		if (bp > 0.f)
			want += unspent / bp;
	}
	const int have = ConsOwnedAny() + ConsInFlightAny();
	return (float(have) < want) ? (int(want) - have) : 0;
}

// How far under the floor we are. The floor SCALES WITH INCOME -- one con
// plus one per 25 metal/s (apexearth 2026-08-23: "at 100 metal per second we
// should have at least 5"). Any lab qualifies: air, bot or vehicle cons all
// reach the ceiling, and the ReachesCeiling test is def-based, not lab-based.
int CeilingConsNeed()
{
	const float per = ai.GetTunable("apex_t2_con_per_m", TUNE_T2_CON_PER_M);
	float want = ai.GetTunable("apex_t2_con_base", TUNE_T2_CON_BASE)
			+ aiEconomyMgr.metal.income / ((per > 1.f) ? per : 25.f);
	// Unspent metal is hands we lack, at the ceiling tier as at the first:
	// Carrot at 30 min, 9 T2 cons to BARb's 13 and 9 mohos to 18 with 6k
	// metal spilled per game (2026-09-08).
	const float unspent = UnspentByHands();
	if (unspent > 0.f) {
		const float bp = ConWorkerBP();
		if (bp > 0.f)
			want += unspent / bp;
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
	float m = 0.f;
	for (uint i = 0; i < Brain::gFQPendDef.length(); ++i) {
		CCircuitDef@ pd = Brain::gFQPendDef[i];
		if (pd is null)
			continue;
		const int d = int(pd.id);
		if (!Catalog::gMobile[d] || Catalog::gBuilder[d]
			|| (Catalog::gPower[d] <= 1.f) || Catalog::gKamikaze[d])
			continue;
		m += Catalog::gCostM[d];
	}
	return m;
}

// Why the last ConOrderFor call declined. The facqueue logs it when a line
// comes back with nothing: an election that orders nothing is idle factory
// time, and until this existed the reason was invisible.
string gNoOrder = "";

// The line's own ranking, defrank's pattern (his zero-Titan report at
// ~500 m/s: which TERM zeroes a candidate is invisible in every log, and a
// hosted game leaves no infolog to read it from afterwards). One line per
// factory def per minute: every mobile combat candidate with its draw
// weight (v x1000, decide's convention) or the reason it never entered.
array<int> gNextProdRankOf;
int gNextRezLog = 0;

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
	return gMSpareEma * ((fillS > 1.f) ? fillS : 180.f);
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
	const float armyT0 = ArmyTarget();
	const float armyVal0 = ArmyValue();
	const float armyFlight0 = ArmyInFlightM();
	const float armyHave = armyVal0 + armyFlight0;
	const bool ovfHands = OverflowBuysHands();
	const float richGap = RichArmyGapM();
	if ((ceilNeed <= 0) && !gMexOpen && (upD <= 0.5f) && (bpGap <= 0.5f)
		&& (armyT0 - armyHave <= 0.5f)
		&& (richGap <= 0.5f))
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
	// COVERAGE IS ARMY DEMAND: the light units the base still needs so a
	// guard stands by every building (military/guardposts.as, his "units
	// are cover" ruling). Not a share of income -- what the base's own
	// spread asks for, and it grows with the base, never with a clock.
	float coverShare = 0.f;   // how much of the gap is coverage, 0..1
	{
		const float coverGap = Military::CoverNeedM() - armyFlight0;
		if (coverGap > armyGap)
			armyGap = coverGap;
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
	if (!ovfHands && (richGap > armyGap))
		armyGap = richGap;
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
	float rezRestore = 0.f, rezStream = 0.f, rezCap = 0.f;
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
	{
		const float drainR = ai.GetTunable("apex_request_drain", TUNE_REQUEST_DRAIN);
		const float hands = aiEconomyMgr.metal.income
				/ ((drainR > 1.f) ? drainR : 7.f)
				* ai.GetTunable("apex_con_feed_headroom", TUNE_CON_FEED_HEADROOM);
		float ownedHands = 0.f;
		for (uint hd = 1; hd < gOwnCount.length(); ++hd) {
			if ((gOwnCount[hd] > 0) && Catalog::gMobile[int(hd)]
				&& Catalog::gBuilder[int(hd)] && !Catalog::gRezzer[int(hd)])
				ownedHands += float(gOwnCount[hd]);
		}
		if (hands > 0.5f) {
			feedRoom = (hands - ownedHands) / hands;
			if (feedRoom < 0.f)
				feedRoom = 0.f;
		}
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
		if (ovfHands) {
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
	const float tPatrolShort = PatrolShort();
	const float tFoeSpeed = FoeSpeedCap();
	const bool ecoRoleOn = EcoRoleActive();
	const bool ecoQuietOn = EcoQuiet();
	const float bestExt = BestExtract();
	const float incA = aiEconomyMgr.metal.income;
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
		const float eI = aiEconomyMgr.energy.income;
		const float eP = aiEconomyMgr.energy.pull;
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
	// RoleTarget and RoleValue are per ROLE, and a line offers far more
	// candidates than roles. Linear over at most a handful of entries.
	array<int> rcRole;
	array<float> rcTgt;
	array<float> rcVal;
	for (uint i = 0; i < prods.length(); ++i) {
		const int d = prods[i];
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d])
			continue;
		if (EcoOnly() && !Catalog::gBuilder[d])
			continue;   // the economy-only benchmark: hands only
		if (t1AirMute && !Catalog::gBuilder[d] && (Catalog::gPower[d] > 1.f))
			continue;
		// SUPPORT: mobile eyes and static-cover. One radar and one jammer per
		// squad that can actually take one (apexearth: "we only need up to 2 of
		// these per squad that we have"); attachment is the military layer's,
		// production is ours.
		//
		// AN ARMED UNIT IS ARMY. gRadar/gJammer also flag anything carrying
		// radarDistance > 900 or jam > 100, which is a Commando, a Phantom and
		// a battleship -- priced here they never entered the army market at
		// all, and each one drew its own copy of the demand below.
		if (Catalog::gMobile[d] && !Catalog::gBuilder[d]
			&& (Catalog::gSurfT[d] + Catalog::gAirT[d] < 0.01f)
			&& (Catalog::gRadar[d] || Catalog::gJammer[d]))
		{
			SupportCensus();
			const bool isJamS = !Catalog::gRadar[d];
			const float haveS = isJamS ? gSupJamN : gSupRadarN;
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
		// gain is zero and the line builds army as before.
		if (!Catalog::gBuilder[d] && Air::IsBomberDef(d)) {
			const float gainB = Air::StrikeGainFor(d, fillS) * roleMul;
			if (gainB > 0.f) {
				const float vB = gainB / Catalog::gCostM[d];
				candDef.insertLast(d);
				candV.insertLast(vB);
				candGain.insertLast(gainB);
				sumV += vB;
				continue;
			}
		}
		// ESCORT: a guard for a worker walking outside safe ground. Priced,
		// not decreed -- see EscortGain. Eligibility stays the military hook's
		// (EscortWorthy), because anything else ordered here would be produced
		// and then refuse the duty.
		Market::EscortFieldCensus();
		if (!Catalog::gBuilder[d] && EscortWorthy(d)) {
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
				float unmet = rezStream - float(rezHave) * rezCap;
				if (unmet > rezCap)
					unmet = rezCap;
				rezRestore = ((unmet > 0.f) ? unmet : 0.f) * roleMul;
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
			const float sinkGap = ovfHands ? 0.f : (richGap * roleMul);
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
				if (floatVal < 0.f)
					floatVal = Military::EnemyAfloat()
							? (Military::EnemyCostOf(Unit::Role::SUB.type)
								* AnswerShare()) : 0.f;
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
				ppc *= 1.f + tCoverWorth * CoverPerMetal(d) * tPatrolShort;
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
							* dash * tPatrolShort / (mineM / gWMCost);
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
			const float rTarget = rcTgt[rSlot];
			const float rGap = rTarget - rcVal[rSlot];
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
			pLineSum += ppc / linePPC;
			++pLineN;
			if (prankNow)
				prank += " " + Catalog::Def(d).GetName()
					+ "=" + formatFloat(vA * 1000.f, "", 0, 2)
					+ "(g" + formatFloat(gainA, "", 0, 2)
					+ ",p" + formatFloat(ppc / linePPC, "", 0, 3)
					+ ",r" + formatFloat(roleW, "", 0, 2)
					+ ",a" + formatFloat(affM, "", 0, 2) + ")";
			continue;
		}
		// An ARMED producible builder is a decoy-class unit: it pays for a
		// gun and a disguise nobody asked for (apexearth: "do not want
		// them; maybe useful for later logic").
		if (Catalog::gSurfT[d] + Catalog::gAirT[d] > 0.01f)
			continue;
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
		if (consNeedA > 0) {
			AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName()
				+ " #" + fac.id + " -> produce:" + Catalog::Def(d).GetName()
				+ " (con floor need=" + consNeedA
				+ " have=" + ConsOwnedAny()
				+ " inflight=" + ConsInFlightAny()
				+ " inc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
				+ " hands=" + formatFloat(EtaHandsShare(), "", 0, 2) + ")");
			return Catalog::Def(d);
		}
		if ((ceilNeed > 0) && ReachesCeiling(d)) {
			AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName()
				+ " #" + fac.id + " -> produce:" + Catalog::Def(d).GetName()
				+ " (t2-con floor need=" + ceilNeed
				+ " have=" + CeilingConsOwned()
				+ " inflight=" + CeilingConsInFlight()
				+ " inc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1) + ")");
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
			if (float(landT1) >= tEcoConKeep + 2.f)
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
		gain += mob * ((over < drain) ? over : drain);
		if (gMexOpen && (reach > 0.f)) {
			// A con claims spot after spot -- a stream of STREAMS -- but the
			// STREAMS ARE FINITE: 37 cons once chased 13 spots and easy BARb
			// walked over an armyless base (measured, ladder game 1). The
			// claim gain divides by claimers per open spot -- the unserved-
			// demand law, fourth application.
			CacheSpots();
			const float open = float(int(gAllSpots.length()) - int(gLSpot.length()));
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
			gain += mob * util * SpotM() * (((fillS > 1.f) ? fillS : 180.f) / 60.f)
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
		// the closed-loop room. The tier floors above already guarantee
		// the minimums, so zero here starves nothing essential.
		if (!Catalog::gRezzer[d])
			gain *= feedRoom;
		if (gain <= 0.5f) {
			// A cut candidate leaves no trace otherwise -- it is absent from
			// prodrank, so "we stopped making pawns" reads as a lost election
			// rather than a unit that was never offered.
			if (prankNow)
				prank += " " + Catalog::Def(d).GetName()
					+ ":cut(g" + formatFloat(gain, "", 0, 3) + ")";
			continue;
		}
		const float v = gain / Catalog::gCostM[d];
		candDef.insertLast(d);
		candV.insertLast(v);
		candGain.insertLast(gain);
		sumV += v;
	}
	if (rezDef >= 0) {
		const float pLine = (pLineN > 0) ? (pLineSum / float(pLineN)) : 1.f;
		const float hM = (fillS > 1.f) ? fillS : 60.f;
		const float pMedic = rezRestore * hM / Catalog::gCostM[rezDef] * pLine;
		const float gainM = ((armyGap > 0.f) ? armyGap : 0.f) / hM * pMedic * stakeMul;
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
			+ " inc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
			+ " gap=" + int(armyGap)
			+ " n=" + candDef.length() + prank);
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
		+ " hands=" + formatFloat(EtaHandsShare(), "", 0, 2) + ")");
	return Catalog::Def(best);
}


}  // namespace Market
