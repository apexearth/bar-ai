namespace Market {
int gMetalFirstCut = 0;   // wants dropped while the unlock is starved
//------------------------------------------------------------------------------
// The arbiter's builder side. Called only from Brain::Decide.
//------------------------------------------------------------------------------
// PERF NESTING. Perf::Add is a flat accumulator, so the ONLY summable children
// of hk.maketask.builder are:
//   bld.flee + bld.rezzer + want.* + dec.* + exec.want + residual
// The rest are views or grandchildren: xk.<kind> is exec.want's own interval
// under a second name, xw.* is inside ExecuteWant, memo.* is a zero-duration
// Note. want.* is charged from BOTH ElecPump calls (maketask's prologue and
// Decide's); dec.* and exec.want are Decide's alone.
//------------------------------------------------------------------------------

int gNextIdleLog = 0;
int gNextAuctionDiag = 0;
int gNextAaPanicLog = 0;
int gNextDefPanicLog = 0;
int gNextHoistLog = 0;
array<int> gLastDecideAt(32001, -30000);   // per-unit-id, Spring ids cap at 32k
// THE JOB A HAND IS ON IS A CANDIDATE, NOT A BLANK. C++ hides the unit's
// assignment before every re-election, so the hold in maketask.as never
// sees it and a walking constructor rolled the draw afresh every 3 s --
// a 60 s walk survived only if twenty rolls all landed on the same
// category (his watch: "constructors go on long journeys, get to the
// other side and turn around"). The incumbent's walk is partly paid, so
// its value only rises en route: a drawn challenger must beat it; the
// hoists (estall, cover, role) still override.
array<IUnitTask@> gIncTask(32001);
array<float> gIncVal(32001, 0.f);
int gKeepJob = 0;
int gKeepMin = 0;      // keeps this minute
int gOffCrewMin = 0;   // incumbents forgotten because the hand was taken off them
int gNextKeepLog = 0;
// Which builder may drop its work for the first AA tower, and when it claimed
// that. One at a time: the tower is 80 metal, abandoning every frame in the
// base is not.
int gAaClaim   = -1;
int gAaClaimAt = -30000;
// Same one-at-a-time claim for the ground-defence panic.
int gDefClaim   = -1;
int gDefClaimAt = -30000;

// Why a builder ends an election holding nothing: per-kind count of wants
// that ranked but could not be turned into a task.
array<int> gExecFail(32, 0);
int gExecNone = 0;
int gComFwdLogAt = -999999;   // see the commander forward skip in the exec loop
int gNextExecLog = 0;
int gNextComRefuseLog = 0;

// The decide and exec lines are one ~20-term concatenation per election and per
// execution, built whether or not anyone reads the infolog. On by default --
// review.py, trace.py, rebuild_lag.py and audit.py all parse them.
int gDecideLogOn = -1;
bool DecideLogOn()
{
	if (gDecideLogOn < 0)
		gDecideLogOn = (ai.GetTunable("apex_decide_log", TUNE_DECIDE_LOG) > 0.f) ? 1 : 0;
	return gDecideLogOn > 0;
}

//------------------------------------------------------------------------------
// THE ELECTION MEMO. A proposer's answer is the WORLD (site auctions, target
// scans, ladder rankings -- slow) plus the ASKER (walk time, eligibility --
// fast, and shared by every builder of one def). The stack re-derived the
// world for every asking builder: measured on a 37-min 1v1 at ~1700 m/s with
// 655 builders, 407 full stacks a minute at ~9.5ms each -- the largest single
// AI cost and the 30-146ms sim hitches. So the six proven-expensive proposers
// share their answer per ASKING DEF for MEMO_TTL, and an EXECUTED want evicts
// its kind at once: the execution changes the very counts that priced it, and
// serving the stale copy to the next builder is the stampede bug in one line.
// Only proposers whose site is world-anchored may sit here -- mex, geo and
// mexup pick spots relative to the asker and stay live. The handed-out want
// is always a COPY: Decide mutates gain/value in place (retire discount,
// exposure charge), and a shared object would compound those per election.
//------------------------------------------------------------------------------
// THE CEILING, NOT THE VALIDITY TEST. Validity is MemoKey below -- the stamps of
// the data the answer was computed from. This only bounds the half no stamp can
// reach: every cached value runs through ValueOf, whose income, pull, bank, wage
// and build-power terms move EVERY frame (price.as:388-533), so a copy is always
// mispriced by however old it is. Default 45 is what the clock alone used to be,
// which makes this the throughput knob and its default behaviour-preserving.
int gMemoTtl = -1;
int MemoTtl()
{
	if (gMemoTtl < 0)
		gMemoTtl = int(ai.GetTunable("apex_memo_ttl", TUNE_MEMO_TTL));
	return (gMemoTtl > 1) ? gMemoTtl : 1;
}
// One more mex matters less the more income already stands, so the spot
// answer is re-asked once per that many mexes' worth of time (apexearth
// 2026-09-20); an executed claim still evicts it at once.
int MemoTtlMex()
{
	const float spot = SpotM() * IncomeMult();
	const float inc = aiEconomyMgr.metal.income;
	const float n = (spot > 0.f) ? (inc / spot) : 1.f;
	return MemoTtl() * int((n > 1.f) ? n : 1.f);
}
// A copy this old ALWAYS recomputes, on its own bounded budget. The stack
// calls the memo slots in one fixed order, so energy+tech drained the whole
// 2-per-frame budget on every election and protect served its frame-25
// empty answer for MINUTES (measured 2026-08-30 via prot-enter: first real
// protect run at 4.4-16 min depending on the game; the commander's never
// ran at all -- which is why the first mexes stood naked for the tick).
const int   MEMO_STARVED = 450;   // 15s
const uint  MEMO_N = 9;
// The mex slot keeps gMexOpen with its answer: a served copy must leave the
// other proposers reading what the computation read.
array<bool> gMemoMexOpen;
array<array<int>@> gMemoAt;     // per slot: per-askerDef frame stamp
array<array<Want@>@> gMemoW;    // per slot: the pristine cached answer
// A starved copy that was ALREADY deferred once recomputes next time whatever
// the budget says. The stack calls the slots in one fixed order, so the two
// starved recomputes a frame always went to the same two slots, and a def
// that decides rarely -- the commander, every minute or two -- never got past
// them: his protect copy stayed the frame-25 empty answer until another
// builder's execution evicted it.
array<array<bool>@> gMemoDeferred;
// An eviction invalidates one KIND, so the memo carries the reverse index: per
// kind, the cells holding an answer of that kind. Walking MEMO_N x every def
// instead was ~3.1M iterations a game.
array<array<int>@> gMemoKindCells;   // kind -> packed slot*stride + askerDef
array<array<int>@> gMemoKindPos;     // per cell: its index in that kind's list
int gMemoStride = 0;
// The stamps of what each slot reads, so an entry dies when its inputs move
// rather than when a timer runs out. NOT COVERED, and named because it cannot
// be fixed from here: six of the seven slots read the commitment ledger or
// Requests::gLive and NOTHING stamps either, so an order by another builder
// moves an input this key cannot see. MemoEvictKind covers the executed kind
// only. See docs/27, apex_memo_ttl.
array<array<int>@> gMemoKey;   // per slot: per-askerDef validity key

// FOUR OF THE SEVEN PICK THEIR SITE FROM THE ASKER'S OWN POSITION -- protect and
// sense take the nearest gap or slot, obsolete-reclaim the nearest victim, mexup
// the nearest spot -- so one answer per def was one builder's site handed to
// every other builder of its kind, which is the rule in this header ("only
// proposers whose site is world-anchored may sit here") broken in four places.
// The asker's cell joins their key: builders standing together still share, and
// a builder across the base gets its own answer. The cell is the light tower's
// reach, this tree's unit for "the same piece of ground".
float gMemoCell = 0.f;
int MemoKey(int slot, CCircuitUnit@ unit)
{
	// The stall state is an input: a tower priced on a full bank was served
	// 16 s later with the bank at 10, its 680 E bill still forgiven.
	int k = gOwnSetStamp * 4 + (HardEStall() ? 1 : 0)
			+ (aiEconomyMgr.isEnergyFull ? 2 : 0);
	if ((slot == 3) || (slot == 4) || (slot == 5))
		k = k * 31 + gPfAt * 7 + Military::gFrontStamp;
	if (slot == 8)
		k = k * 31 + gLStamp;
	if ((slot == 3) || (slot == 4) || (slot == 5) || (slot == 6) || (slot == 8)) {
		if (gMemoCell <= 1.f)
			gMemoCell = Brain::LightTowerRange();
		const AIFloat3 p = unit.GetPos(ai.frame);
		k = k * 31 + int(p.x / gMemoCell) * 4093 + int(p.z / gMemoCell);
	}
	return k;
}

Want@ WantCopy(Want@ s)
{
	if (s is null)
		return null;
	Want c;
	c.kind = s.kind;
	@c.def = s.def;
	c.pos = s.pos;
	c.spotId = s.spotId;
	@c.target = s.target;
	c.retire = s.retire;
	c.gain = s.gain;
	c.mCost = s.mCost;
	c.tCost = s.tCost;
	c.value = s.value;
	c.buildSec = s.buildSec;
	c.walkSec = s.walkSec;
	return c;
}

Want@ MemoSlotCall(int slot, CCircuitUnit@ unit)
{
	if (slot == 0) return ProposeEnergy(unit);
	if (slot == 1) return ProposeTech(unit);
	if (slot == 2) return ProposeNano(unit);
	if (slot == 3) return ProposeSense(unit);
	if (slot == 4) return ProposeReclaimObsolete(unit);
	if (slot == 6) return ProposeMexUp(unit);
	if (slot == 7) return ProposePlant(unit);
	if (slot == 8) return ProposeMex(unit);
	return ProposeProtect(unit);
}

// The reverse index is maintained on the one line that writes a cached answer:
// unlink the cell from the kind it used to hold, then link it to the new one.
// Swap-remove, so both halves are O(1).
void MemoUnlink(int slot, int ud)
{
	Want@ old = gMemoW[slot][ud];
	if (old is null)
		return;
	const int k = old.kind;
	if ((k < 0) || (uint(k) >= gMemoKindCells.length()) || (gMemoKindCells[k] is null))
		return;
	array<int>@ cells = gMemoKindCells[k];
	const int at = gMemoKindPos[slot][ud];
	if ((at < 0) || (uint(at) >= cells.length()))
		return;
	const int last = int(cells.length()) - 1;
	if (at != last) {
		const int moved = cells[last];
		cells[at] = moved;
		gMemoKindPos[moved / gMemoStride][moved % gMemoStride] = at;
	}
	cells.removeLast();
	gMemoKindPos[slot][ud] = -1;
}

void MemoLink(int slot, int ud, Want@ w)
{
	gMemoKindPos[slot][ud] = -1;
	if (w is null)
		return;
	const int k = w.kind;
	if (k < 0)
		return;
	if (gMemoKindCells.length() <= uint(k))
		gMemoKindCells.resize(uint(k) + 1);
	if (gMemoKindCells[k] is null) {
		array<int> a;
		@gMemoKindCells[k] = a;
	}
	gMemoKindPos[slot][ud] = int(gMemoKindCells[k].length());
	gMemoKindCells[k].insertLast(slot * gMemoStride + ud);
}

// ONE MORE SERVING OF A STALE ANSWER BEATS TWO HEAVY REFRESHES IN ONE FRAME
// (his rule: "we don't want to ever do too much in any one frame... we
// should be distributing operations across multiple frames"). At most two
// memo cores recompute per sim frame; a stale slot past the cap serves its
// cached copy one election longer -- DefSiteFill's fills-per-frame shape,
// lifted to the memo. A slot with nothing cached always computes (it cannot
// serve what it never had), and an EVICTED slot recomputes too: its stamp
// is reset to the never-filled marker, because the eviction means the
// cached answer was consumed and re-serving it is the stampede bug.
int gMemoFreshFrame = -1;
int gMemoFreshN = 0;
int gMemoStarvN = 0;

Want@ MemoPropose(int slot, CCircuitUnit@ unit)
{
	if (gMemoAt.length() == 0) {
		gMemoAt.resize(MEMO_N);
		gMemoW.resize(MEMO_N);
		gMemoDeferred.resize(MEMO_N);
		gMemoKindPos.resize(MEMO_N);
		gMemoKey.resize(MEMO_N);
		gMemoStride = Catalog::gDefCount + 1;
		gMemoMexOpen.resize(uint(Catalog::gDefCount + 1));
		for (uint s = 0; s < MEMO_N; ++s) {
			array<int> a(uint(Catalog::gDefCount + 1), -30000);
			array<Want@> ws(uint(Catalog::gDefCount + 1));
			array<bool> df(uint(Catalog::gDefCount + 1), false);
			array<int> kp(uint(Catalog::gDefCount + 1), -1);
			array<int> mk(uint(Catalog::gDefCount + 1), 0);
			@gMemoAt[s] = a;
			@gMemoW[s] = ws;
			@gMemoDeferred[s] = df;
			@gMemoKindPos[s] = kp;
			@gMemoKey[s] = mk;
		}
	}
	const int ud = int(unit.circuitDef.id);
	if ((ud < 1) || (ud > Catalog::gDefCount))
		return MemoSlotCall(slot, unit);
	// Valid while nothing it was computed from has moved AND inside the ceiling
	// the per-frame prices need.
	const int key = MemoKey(slot, unit);
	if ((gMemoKey[slot][ud] == key)
		&& (ai.frame - gMemoAt[slot][ud] < ((slot == 8) ? MemoTtlMex() : MemoTtl()))) {
		Perf::Note("memo.hit");
		if (slot == 8)
			gMexOpen = gMemoMexOpen[ud];
		return WantCopy(gMemoW[slot][ud]);
	}
	if (gMemoFreshFrame != ai.frame) {
		gMemoFreshFrame = ai.frame;
		gMemoFreshN = 0;
		gMemoStarvN = 0;
	}
	if ((gMemoAt[slot][ud] > -30000) && (gMemoFreshN >= 2)) {
		// Past the normal budget: only a STARVED copy may still recompute,
		// and at most two of those a frame -- see MEMO_STARVED above --
		// unless it was starved AND deferred the last time it was asked.
		const bool starved = ai.frame - gMemoAt[slot][ud] > MEMO_STARVED;
		if (!starved || ((gMemoStarvN >= 2) && !gMemoDeferred[slot][ud])) {
			Perf::Note("memo.defer");
			if (starved)
				gMemoDeferred[slot][ud] = true;
			if (slot == 8)
				gMexOpen = gMemoMexOpen[ud];
			return WantCopy(gMemoW[slot][ud]);
		}
		++gMemoStarvN;
	}
	++gMemoFreshN;
	Perf::Note("memo.miss");
	Want@ fresh = MemoSlotCall(slot, unit);
	if (slot == 8)
		gMemoMexOpen[ud] = gMexOpen;
	gMemoAt[slot][ud] = ai.frame;
	gMemoKey[slot][ud] = key;
	gMemoDeferred[slot][ud] = false;
	MemoUnlink(slot, ud);
	@gMemoW[slot][ud] = fresh;
	MemoLink(slot, ud, fresh);
	return WantCopy(fresh);
}

// THE FRAME'S ELECTION SLICE. Spend is charged AS IT HAPPENS and tested between
// proposers, which is the only way it can bound the frame it is checked on: the
// old budget was tested at the door of the whole election and charged after it
// returned, so it stopped the next builder and never this one. Everything else
// here follows from that -- the set is assembled a few steps at a time and
// Decide holds the builder at null until it is whole.
// The trade, the numbers and how to move it: docs/27, apex_elec_frame_us.
int gElecFrame = -1;
double gElecSpentUs = 0.0;
double gElecPumpUs = 0.0;   // of gElecSpentUs, what the pump's steps took
double gElecCallUs = 0.0;   // of that, what THIS call has already charged itself
double gElecBudgetUs = -1.0;
bool gElecFinishing = false;

// 19 proposers, then the finish: rank, price the exposure, hoist the panics,
// draw, execute. The finish is a step of its own because it is the other half
// of the frame cost, and a frame with nothing left to spend must be able to
// hold it over exactly the way it holds a proposer over.
const int ELEC_STEPS = 20;
// Each step's own measured cost. A step is opened only when what it is EXPECTED
// to cost still fits the slice -- checking after the fact leaves the frame
// carrying the overshoot, which is the bug this replaces.
array<double> gStepEma(uint(ELEC_STEPS), 0.0);

double ElecFrameUs()
{
	if (gElecBudgetUs < 0.0)
		gElecBudgetUs = double(ai.GetTunable("apex_elec_frame_us",
				TUNE_ELEC_FRAME_US));
	return gElecBudgetUs;
}

void ElecFrameRoll()
{
	if (gElecFrame != ai.frame) {
		gElecFrame = ai.frame;
		gElecSpentUs = 0.0;
		gElecPumpUs = 0.0;
	}
}

void ElecSpend(double us)
{
	ElecFrameRoll();
	if (us > 0.0)
		gElecSpentUs += us;
}

// What the caller (maketask.as) owes on top of what the election charged itself:
// the prologue, the safety rungs and the finish stage. Every return path still
// counts without instrumenting each one, and nothing is counted twice.
void ElecSpendRest(double totalUs)
{
	double rest = totalUs - gElecCallUs;
	if (rest < 0.0)
		rest = 0.0;
	if (gElecFinishing) {
		// The finish is not timed on its own -- it has a dozen return paths --
		// so its estimate is this call's whole remainder. That over-counts the
		// prologue into it, which errs toward holding the finish over.
		gElecFinishing = false;
		const uint fs = uint(ELEC_STEPS) - 1;
		gStepEma[fs] = (gStepEma[fs] <= 0.0) ? rest
				: (gStepEma[fs] * 0.8 + rest * 0.2);
	}
	gElecCallUs = 0.0;
	ElecSpend(rest);
}

bool ElecAfford(int step)
{
	ElecFrameRoll();
	if (gElecSpentUs <= 0.0)
		return true;   // a step dearer than the whole slice must still run once
	// The finish is budgeted against finishes only: the pump spends the slice
	// on other sets' steps at the door of every hook call, and a whole set's
	// own visit would otherwise find nothing left, every visit.
	const double spent = (step == ELEC_STEPS - 1) ? (gElecSpentUs - gElecPumpUs) : gElecSpentUs;
	return spent + gStepEma[uint(step)] <= ElecFrameUs();
}

void ElecCharge(int step, double us)
{
	if (us < 0.0)
		us = 0.0;
	gStepEma[uint(step)] = (gStepEma[uint(step)] <= 0.0) ? us
			: (gStepEma[uint(step)] * 0.8 + us * 0.2);
	gElecCallUs += us;
	ElecSpend(us);
}

// One partly-assembled want set. Keyed by unit id and validated by def: a slot
// whose owner died and whose id the engine handed to a different unit reads as
// a different def and is thrown away rather than finished for the wrong builder.
class Elec {
	int defId = -1;
	int askedAt = -30000;   // last ask; nobody asks for a dead builder's slot
	int startFrame = 0;     // when this set opened -- its age, and the draw's clock
	int step = 0;           // the next step to run
	array<Want@> wants;
	// THE STACK IS NOT ORDER-FREE ACROSS BUILDERS. ProposeMex writes two
	// namespace values that the plant and the three reclaim proposers read back
	// in the same election -- whether any mex spot is open TO THIS ASKER
	// (want_mex.as:450 -> want_plant.as:832, want_reclaim.as:166) and what the
	// best spot yields (want_mex.as:554 -> SpotM() -> want_plant.as:761). Within
	// one builder the slice keeps the order; BETWEEN builders it could drop
	// another asker's probe in between, so the set carries its own copy.
	bool sMexOpen = false;
	float sSpotM = -1.f;
}
array<Elec@> gElecOf(32001);   // per-unit-id, Spring ids cap at 32k
// A builder that STOPS ASKING has taken a task elsewhere or died, and its
// half-built set answers a world that has moved on. The engine gives an idle
// builder one AiMakeTask per pass of its idle set, and a pass is at most
// TEAM_SLOWUPDATE_RATE (15) runs of CBuilderManager::UpdateIdle, which runs
// every 8 frames -- so silence for twice that is abandonment, not a pause.
// Only silence resets a set: being held back by the budget must not, or a
// saturated frame would restart the very elections it is starving.
const int ELEC_LAPSE = 2 * 15 * 8;   // frames
// Silence is a multiple of the revisit period as MEASURED: with 300 idle
// builders the pass outran the fixed 8 s, and every sliced set expired
// before its own builder came back to collect it.
float gRevisitEma = 0.f;   // frames between one builder's visits
int ElecLapse()
{
	const int byVisit = int(4.f * gRevisitEma);
	return (byVisit > ELEC_LAPSE) ? byVisit : ELEC_LAPSE;
}

// THE PENDING SETS, OLDEST FIRST. FIFO is the whole aging rule: the slice goes
// to the election that has waited longest, and one that wins finishes and
// leaves, so nothing is jumped and nothing starves. Only unit IDS live here --
// CCircuitUnit is NOCOUNT and must never be stored (commit.as) -- and
// ai.GetTeamUnit is this tree's aliveness test for them.
array<int> gElecQ;
int gElecWorstWait = 0;
int gElecPartial = 0;
int gElecDone = 0;
int gElecDropped = 0;
int gElecDropLapse = 0;   // silent past ELEC_LAPSE
int gElecDropTask = 0;    // put on a build since it opened
int gElecHeld = 0;        // whole, and the slice could not afford the finish
int gDecBounce = 0;       // the 2-s re-election gate
int gNextElecLog = 0;

// The nineteen proposers, one per step, IN THE ORDER THE ATOMIC STACK RAN THEM.
// That order is load-bearing, not cosmetic: ProposeMex's probe feeds the plant
// and the three reclaim proposers (see class Elec). Slicing preserves it, so a
// set assembled over five frames is priced the same way one assembled in one is.
Want@ ProposeStep(int step, CCircuitUnit@ unit)
{
	const double _t = Perf::T0();
	Want@ w = null;
	if (step == 0)       { @w = MemoPropose(8, unit);         Perf::Add("want.mex", _t); }
	else if (step == 1)  { @w = MemoPropose(0, unit);         Perf::Add("want.energy", _t); }
	else if (step == 2)  { @w = ProposeGeo(unit);             Perf::Add("want.geo", _t); }
	else if (step == 3)  { @w = MemoPropose(7, unit);         Perf::Add("want.plant", _t); }
	else if (step == 4)  { @w = ProposeConvert(unit);         Perf::Add("want.convert", _t); }
	else if (step == 5)  { @w = ProposeStore(unit);           Perf::Add("want.store", _t); }
	// Memoised: unmemoised this one is O(builders x mex spots) and grows all game.
	else if (step == 6)  { @w = MemoPropose(6, unit);         Perf::Add("want.mexup", _t); }
	else if (step == 7)  { @w = MemoPropose(1, unit);         Perf::Add("want.tech", _t); }
	else if (step == 8)  { @w = MemoPropose(2, unit);         Perf::Add("want.nano", _t); }
	else if (step == 9)  { @w = MemoPropose(4, unit);         Perf::Add("want.reclobs", _t); }
	else if (step == 10) { @w = ProposeReclaimBlocker(unit);  Perf::Add("want.reclblk", _t); }
	else if (step == 11) { @w = ProposeReclaimPenned(unit);   Perf::Add("want.reclpen", _t); }
	else if (step == 12) { @w = ProposeReclaimSquatter(unit); Perf::Add("want.reclsqt", _t); }
	else if (step == 13) { @w = ProposeFactoryGuard(unit, ProposeAssist(unit));  Perf::Add("want.assist", _t); }
	else if (step == 14) { if (!EcoOnly()) @w = MemoPropose(5, unit);  Perf::Add("want.protect", _t); }
	else if (step == 15) { if (!EcoOnly()) @w = ProposeTeeth(unit);    Perf::Add("want.teeth", _t); }
	else if (step == 16) { @w = MemoPropose(3, unit);         Perf::Add("want.sense", _t); }
	else if (step == 17) { if (!EcoOnly()) @w = ProposeAirDef(unit);   Perf::Add("want.airdef", _t); }
	else                 { if (!EcoOnly()) @w = ProposeSuper(unit);    Perf::Add("want.super", _t); }
	ChargeTrip(w, unit);
	return w;
}

// EVERY WANT PAYS THE ASKER'S ROAD, not only the mex want: a T2 con walked
// 6,000 elmo to raise an advanced radar and a flak at an outpost mex and
// died there (his 1v1, minute 20). The charge is the expected loss on the
// trip -- TripRisk times what the asker is worth, the commander being worth
// everything we own -- and it is assigned, not accumulated, because memoed
// wants come back as the same object.
void ChargeTrip(Want@ w, CCircuitUnit@ unit)
{
	if ((w is null) || (w.kind == WK_NONE) || (w.kind == WK_MEX) || !OnMap(w.pos))
		return;
	const float c = w.mCost + w.tCost;
	if ((c <= 0.f) || (w.value <= 0.f))
		return;
	if (w.tripM <= 0.f)
		w.valueRaw = w.value;
	const float worth = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
			? (gAssetsM + ArmyValue()) : Catalog::gCostM[int(unit.circuitDef.id)];
	w.tripM = TripRiskFrom(unit.GetPos(ai.frame), w.pos) * worth;
	w.value = w.valueRaw * c / (c + w.tripM);
}

bool ElecIdOk(CCircuitUnit@ unit)
{
	const int uid = int(unit.id);
	return (uid >= 0) && (uid < int(gElecOf.length()));
}

// A set this builder has already opened and not yet finished. Read at the door
// of Decide: a resumption must not be turned away by the re-election rate gate.
bool ElecPending(CCircuitUnit@ unit)
{
	if (!ElecIdOk(unit))
		return false;
	Elec@ st = gElecOf[int(unit.id)];
	return (st !is null) && (st.defId == int(unit.circuitDef.id))
			&& (st.step < ELEC_STEPS - 1)
			&& (ai.frame - st.askedAt <= ElecLapse());
}

Elec@ ElecOpen(CCircuitUnit@ unit)
{
	const int uid = int(unit.id);
	Elec@ st = gElecOf[uid];
	if (st !is null) {
		const float gap = float(ai.frame - st.askedAt);
		gRevisitEma = (gRevisitEma <= 0.f) ? gap : (gRevisitEma * 0.9f + gap * 0.1f);
	}
	if ((st !is null) && ((st.defId != int(unit.circuitDef.id))
			|| (ai.frame - st.askedAt > ElecLapse()))) {
		ElecDrop(uid);   // and its queue entry: a reopen used to leave a duplicate behind
		@st = null;   // recycled onto another unit, or abandoned -- see ElecLapse
	}
	if (st is null) {
		Elec fresh;
		fresh.defId = int(unit.circuitDef.id);
		fresh.startFrame = ai.frame;
		@st = fresh;
		@gElecOf[uid] = st;
		gElecQ.insertLast(uid);
	}
	st.askedAt = ai.frame;
	return st;
}

void ElecDrop(int uid)
{
	if ((uid >= 0) && (uid < int(gElecOf.length())))
		@gElecOf[uid] = null;
	for (uint i = 0; i < gElecQ.length(); ++i) {
		if (gElecQ[i] == uid) {
			gElecQ.removeAt(i);
			return;
		}
	}
}

// Run steps until the set is whole or the frame's slice runs out. The restore
// at the top is the cross-builder ordering fix -- see class Elec.
bool ElecSteps(CCircuitUnit@ unit, Elec@ st)
{
	if (st.step > 0) {
		gMexOpen = st.sMexOpen;
		gLastSpotM = st.sSpotM;
	}
	while (st.step < ELEC_STEPS - 1) {
		if (!ElecAfford(st.step))
			return false;
		const double t0 = ai.ClockUs();
		st.wants.insertLast(ProposeStep(st.step, unit));
		const double us = ai.ClockUs() - t0;
		ElecCharge(st.step, us);
		gElecPumpUs += us;
		++st.step;
		st.sMexOpen = gMexOpen;
		st.sSpotM = gLastSpotM;
	}
	return true;
}

// THE STEPS DO NOT WAIT FOR THEIR OWN BUILDER TO BE HANDED BACK. The engine
// revisits an idle builder once per pass of its idle set, so tying the step rate
// to that made an election take (idle builders) x (slices) passes -- ten seconds
// with ten of them waiting. A half-built set is state we own, so every builder
// update pumps the queue instead, INCLUDING the ones that return early holding a
// task. The engine's hook now only starts and finishes an election.
void ElecPump()
{
	ElecFrameRoll();
	uint i = 0;
	while (i < gElecQ.length()) {
		if (gElecSpentUs > ElecFrameUs())
			return;
		const int uid = gElecQ[i];
		Elec@ st = ((uid >= 0) && (uid < int(gElecOf.length())))
				? gElecOf[uid] : null;
		CCircuitUnit@ u = (st is null) ? null : ai.GetTeamUnit(uid);
		// Dead, recycled onto another unit, silent past ELEC_LAPSE, or put on a
		// build by the engine since it opened: none of those is still electing,
		// and finishing the set would hand a job to a unit that has one.
		bool gone = (st is null) || (u is null)
				|| (st.defId != int(u.circuitDef.id));
		if (!gone && (ai.frame - st.askedAt > ElecLapse())) {
			gone = true;
			++gElecDropLapse;
		}
		if (!gone) {
			IUnitTask@ held = u.task;
			gone = (held !is null) && (held.GetType() == Task::Type::BUILDER);
			if (gone)
				++gElecDropTask;
		}
		if (gone) {
			++gElecDropped;
			if ((uid >= 0) && (uid < int(gElecOf.length())))
				@gElecOf[uid] = null;
			gElecQ.removeAt(i);
			continue;
		}
		if (!ElecSteps(u, st))
			return;   // the slice ran out inside this set; it keeps its place
		++i;          // whole: it waits for its own update to finish and leave
	}
}

void ElecLog()
{
	if (ai.frame < gNextElecLog)
		return;
	gNextElecLog = ai.frame + 60 * SECOND;
	AiLog("apex: elec-slice done=" + gElecDone + " partial=" + gElecPartial
		+ " held=" + gElecHeld + " bounce=" + gDecBounce
		+ " dropped=" + gElecDropped + " (lapse=" + gElecDropLapse
		+ " task=" + gElecDropTask + ") queued=" + gElecQ.length()
		+ " worstWaitS=" + formatFloat(float(gElecWorstWait) / float(SECOND), "", 0, 2)
		+ " revisitS=" + formatFloat(gRevisitEma / float(SECOND), "", 0, 2)
		+ " sliceUs=" + int(ElecFrameUs())
		+ " keep=" + gKeepMin + " offCrew=" + gOffCrewMin);
	gKeepMin = 0;
	gOffCrewMin = 0;
	gElecDone = 0;
	gElecPartial = 0;
	gElecDropped = 0;
	gElecDropLapse = 0;
	gElecDropTask = 0;
	gElecHeld = 0;
	gDecBounce = 0;
	gElecWorstWait = 0;
}

// An executed want of kind K evicts every cached answer of that kind, for
// every asker class -- see the memo's header comment.
// A want this hand was refused at this site does not win its next draw: an
// unplaceable tower held the top price for twelve minutes while every
// fallthrough bought eco and the first lab never came (his Carrot 8v8).
array<int> gRefUnit;
array<int> gRefKind;
array<int> gRefDef;
array<AIFloat3> gRefPos;
array<int> gRefAt;
int gRefDropped = 0;
int gNextRefLog = 0;
const int REFUSAL_MEMO_S = 45;

void NoteRefused(CCircuitUnit@ unit, Want@ w)
{
	const int did = (w.def is null) ? -1 : int(w.def.id);
	for (uint i = 0; i < gRefUnit.length(); ++i) {
		if ((gRefUnit[i] == int(unit.id)) && (gRefKind[i] == w.kind) && (gRefDef[i] == did)) {
			gRefPos[i] = w.pos;
			gRefAt[i] = ai.frame;
			return;
		}
	}
	if (gRefUnit.length() >= 64) {
		gRefUnit.removeAt(0); gRefKind.removeAt(0); gRefDef.removeAt(0);
		gRefPos.removeAt(0); gRefAt.removeAt(0);
	}
	gRefUnit.insertLast(int(unit.id));
	gRefKind.insertLast(w.kind);
	gRefDef.insertLast(did);
	gRefPos.insertLast(w.pos);
	gRefAt.insertLast(ai.frame);
}

bool RecentlyRefused(CCircuitUnit@ unit, Want@ w)
{
	const int did = (w.def is null) ? -1 : int(w.def.id);
	for (uint i = 0; i < gRefUnit.length(); ++i) {
		if ((gRefUnit[i] != int(unit.id)) || (gRefKind[i] != w.kind) || (gRefDef[i] != did))
			continue;
		if (ai.frame - gRefAt[i] > REFUSAL_MEMO_S * SECOND)
			return false;
		return !OnMap(w.pos) || !OnMap(gRefPos[i]) || (w.pos.distance2D(gRefPos[i]) < 160.f);
	}
	return false;
}

void MemoEvictKind(int k)
{
	if ((k < 0) || (uint(k) >= gMemoKindCells.length()) || (gMemoKindCells[k] is null))
		return;
	array<int>@ cells = gMemoKindCells[k];
	for (uint i = 0; i < cells.length(); ++i) {
		const int cell = cells[i];
		gMemoAt[cell / gMemoStride][cell % gMemoStride] = -30000;
	}
}

// A plant with a frame on the ground or standing. An ORDER is not one: the
// order can still fail to place, and rules that key on it pull the commander
// off the very lab they are waiting for.
bool PlantFramed()
{
	if (Factory::gT1FacUnit !is null)
		return true;
	for (uint ci = 0; ci < ComLen(); ++ci) {
		if (gComState[ci] == CS_ORDERED)
			continue;
		const int d = gComDef[ci];
		if (!Catalog::ValidId(d) || Catalog::gMobile[d]
			|| (Catalog::gBuildsList[d].length() == 0)
			|| (Catalog::gBuildPower[d] <= 0.f))
			continue;
		return true;
	}
	return false;
}

// The market's categories onto the budget's five rows. Only the four with an
// honest counterpart are steered: produce, sense, super and reclaim have no row
// of their own and stay at 1 rather than borrow someone else's shortfall.
float BudgetCatMult(int c)
{
	if ((c == CAT_METAL) || (c == CAT_ENERGY))
		return Brain::BudgetMult(Brain::ECONOMY);
	if (c == CAT_BP)
		return Brain::BudgetMult(Brain::BUILDPOWER);
	if (c == CAT_DEFENCE)
		return Brain::BudgetMult(Brain::DEFENCE);
	if (c == CAT_AIRDEF)
		return Brain::BudgetMult(Brain::AIRDEF);
	return 1.f;
}

// The per-category draw, on a ranked list: the best want of each category
// holds a ticket proportional to its value; the drawn one is hoisted to
// ranked[0]. `salt` varies the roll for a redraw within the same frame.
// `atFrame` is the frame the ELECTION OPENED, not the frame it finished on, so
// a set assembled over several frames rolls the same number an atomic one would
// have rolled. Without that the slice changes the draw for no reason.
// The tickets: one per category, weighted as the draw weighs them. Returns
// their sum; catBest carries each ticket's want.
int gEtaPickLogAt = 0;
int gEtaPickTraceAt = 0;
float DrawWeights(array<Want@>@ ranked, array<int>& out catBest, array<float>& out wt)
{
	catBest.resize(CAT_N + 1);
	wt.resize(CAT_N + 1);
	for (int c = 0; c <= CAT_N; ++c) {
		catBest[c] = -1;   // index into ranked, or -1
		wt[c] = 0.f;
	}
	if (ranked.length() == 0)
		return 0.f;
	for (uint ri = 0; ri < ranked.length(); ++ri) {
		const int c = CategoryOf(ranked[ri].kind);
		if (c < 0)
			continue;
		// ranked is sorted by value descending, so the FIRST want seen
		// for a category is that category's argmax -- this is the
		// "highest value energy" pick, made once per election.
		if (catBest[c] < 0)
			catBest[c] = int(ri);
	}
	// ONE ECONOMIC QUESTION while the ETA is on: extraction, generation and
	// build power are three ways of buying a bigger economy sooner, so the
	// ladder answers them together and they hold ONE ticket between them
	// instead of three. See eta.as; CAT_PRODUCE stays out of the merge.
	array<float> catV(CAT_N + 1, -1.f);   // >=0 overrides a ticket's weight
	gDrawLadderTech = -1;
	gDrawLadderMex = -1;
	if (EtaOn()) {
		int pick = EtaEcoPick(ranked);
		if (pick >= 0) {
			if (ranked[pick].kind == WK_MEX)
				gDrawLadderMex = pick;
			for (int c = 0; c < CAT_N; ++c) {
				if (EtaMergedCat(c))
					catBest[c] = -1;
			}
			int pc = CategoryOf(ranked[pick].kind);
			// THE LADDER STEERS TECH. It already prices the lab as a rung and
			// never acted on it, so T2 came from the lottery on the market
			// price alone (commit 608f14b9). When the lab reaches the target
			// sooner than the best mex, generator or hand, it IS the economy
			// pick -- income-scaled by construction, which is his "afford it
			// once built" and "not late" in one number.
			const int techPick = EtaTechPick(ranked);
			if ((techPick >= 0) && (EtaOfWant(ranked[techPick]) < EtaOfWant(ranked[pick]))) {
				if (ai.GetTunable("apex_eta_trace", 0.f) > 0.f) {
					gLadderTrace = true;
					gLadderTraceS = "";
					EtaOfWant(ranked[techPick]);
					AiLog("apex: eta-trace tech:" + gLadderTraceS);
					gLadderTraceS = "";
					EtaOfWant(ranked[pick]);
					AiLog("apex: eta-trace eco:" + gLadderTraceS);
					gLadderTrace = false;
				}
				AiLog("apex: eta-tech t=" + ai.teamId + " "
					+ ((ranked[techPick].def is null) ? "?" : ranked[techPick].def.GetName())
					+ " eta=" + int(EtaOfWant(ranked[techPick]))
					+ " over " + KindName(ranked[pick].kind)
					+ " eta=" + int(EtaOfWant(ranked[pick]))
					+ " P=" + formatFloat(EcoPowerM(), "", 0, 1));
				pick = techPick;
				pc = CategoryOf(ranked[pick].kind);
				gDrawLadderTech = pick;
			}
			catBest[pc] = pick;
			catV[pc] = EtaEcoWeight(ranked);
			// The ladder's pick carries the best rung's ticket, so a pick the
			// market prices far below that rung wins on the rung's odds and
			// reads why=draw: both geo walks were this.
			{
				int vb = -1;
				for (uint ri = 0; ri < ranked.length(); ++ri) {
					if (EtaMergedCat(CategoryOf(ranked[ri].kind)) && EtaRanks(ranked[ri])) {
						vb = int(ri);
						break;   // ranked is value-sorted
					}
				}
				// Sampled, except a pick priced under half the rung it outranks.
				if ((vb >= 0) && (vb != pick) && ((ai.frame >= gEtaPickLogAt)
						|| (ranked[pick].value < 0.5f * ranked[vb].value))) {
					gEtaPickLogAt = ai.frame + 10 * SECOND;
					AiLog("apex: eta-pick t=" + ai.teamId + " " + KindName(ranked[pick].kind)
						+ ":" + ((ranked[pick].def is null) ? "?" : ranked[pick].def.GetName())
						+ " eta=" + int(EtaOfWant(ranked[pick]))
						+ " v=" + formatFloat(ranked[pick].value, "", 0, 2)
						+ " over " + KindName(ranked[vb].kind)
						+ ":" + ((ranked[vb].def is null) ? "?" : ranked[vb].def.GetName())
						+ " eta=" + int(EtaOfWant(ranked[vb]))
						+ " v=" + formatFloat(ranked[vb].value, "", 0, 2)
						+ " P=" + formatFloat(EcoPowerM(), "", 0, 1)
						+ " eAvail=" + formatFloat(EtaEnergyAvail(), "", 0, 0));
					if ((ranked[vb].kind == WK_MEXUP) && (ai.frame >= gEtaPickTraceAt)) {
						gEtaPickTraceAt = ai.frame + 30 * SECOND;
						gLadderTrace = true;
						gLadderTraceS = "";
						EtaOfWant(ranked[pick]);
						AiLog("apex: eta-pick-trace pick:" + gLadderTraceS);
						gLadderTraceS = "";
						EtaOfWant(ranked[vb]);
						AiLog("apex: eta-pick-trace best:" + gLadderTraceS);
						gLadderTrace = false;
					}
				}
			}
			// A converter, a store or an assist has no rung, and clearing their
			// category's ticket above deleted them from the draw: they keep
			// their market price, so they keep a ticket.
			for (uint ri = 0; ri < ranked.length(); ++ri) {
				if (EtaMergedCat(CategoryOf(ranked[ri].kind)) && !EtaRanks(ranked[ri])) {
					catBest[CAT_N] = int(ri);
					break;   // ranked is value-sorted
				}
			}
		}
	}
	// HOW SHARP THE DRAW IS. Weighting each ticket by its raw value means a
	// want the market itself rates six times worse still wins one election
	// in six -- measured: 34% of elections took a lower-valued want, and a
	// mex valued 594 lost to a wind generator valued 99 (apexearth: "is it
	// a random 'luck of the draw' sort of event in that moment?"). Odds are
	// taken on the value RATIO to the leader raised to a power, so the
	// exponent alone moves between proportional (1, the old behaviour) and
	// argmax (large) without a threshold anywhere: at 2 a six-fold gap is
	// one election in thirty-six, which keeps a never-first category from
	// starving without letting it outbid arithmetic.
	const float lead = ranked[0].value;
	const float sharp = ai.GetTunable("apex_draw_sharp", TUNE_DRAW_SHARP);
	// The horizon's whole output and the commitment exponent do not vary with
	// the category; both were re-read for each of the nine.
	const float payH = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
	const float bitCap = EcoPowerM() * ((payH > 1.f) ? payH : 900.f);
	const float commitSh = ai.GetTunable("apex_commit_sharp", TUNE_COMMIT_SHARP);
	float sumV2 = 0.f;
	for (int c = 0; c <= CAT_N; ++c) {
		if (catBest[c] < 0)
			continue;
		const float v = (catV[c] >= 0.f) ? catV[c]
				: ranked[catBest[c]].value;
		// A COMMITMENT IS NOT SAMPLED. The cost of drawing a worse option
		// scales with what that option costs: a wrong 40-metal wind is
		// noise, a wrong 9700-metal afus is the game (apexearth: "for these
		// things that are so impactful I feel like we need to go with
		// winner takes all. There is only one right choice here"). Measured
		// the same session: EVERY afus bought was a draw override, priced
		// BELOW the runner-up each time -- 6.30 against 11.58, 8.53 against
		// 13.29 -- so the pricing was right and the lottery bought it
		// anyway at ~30% weight.
		//
		// So the exponent rises with how big a bite this candidate takes
		// out of what the economy can produce over the payback horizon.
		// Continuous and threshold-free: cheap wants keep their sampling,
		// and a want that would consume the whole horizon's output is
		// effectively argmax.
		float sh = sharp;
		float bite = 0.f;
		if ((bitCap > 1.f) && (ranked[catBest[c]].def !is null))
			bite = ranked[catBest[c]].def.costM / bitCap;
		// The hand's time is the other thing a wrong draw spends: a 1,984-metal
		// geo read a 4% bite and took the only T2 con for five minutes over a
		// moho priced four times higher. Its own time cost over the same
		// horizon is the bite that says so.
		const float tb = ranked[catBest[c]].tCost / ((payH > 1.f) ? payH : 900.f);
		if (tb > bite)
			bite = tb;
		if (bite > 1.f)
			bite = 1.f;
		sh += bite * commitSh;
		float t = v;
		if ((lead > 0.f) && (sh > 0.f) && (sh != 1.f))
			t = lead * pow(v / lead, sh);
		wt[c] = t;
		sumV2 += t;
	}
	return sumV2;
}

int gTechNotDrawnAt = 0;
int gDrawLadderMex = -1;    // the ranked index the ladder chose as a spot claim, this draw
bool gDrawLadderTaken = false;
int gDrawLadderTech = -1;   // the ranked index the ladder chose as tech, this draw
bool CategoryDraw(CCircuitUnit@ unit, array<Want@>@ ranked, uint salt, int atFrame)
{
	bool didDraw = false;
	array<int> catBest;
	array<float> wt;
	const float sumV2 = DrawWeights(ranked, catBest, wt);
	gDrawLadderTaken = false;
	// AN OPEN SPOT IS NOT SAMPLED EITHER (the plan: a rung is reached when
	// the cheaper growth beneath it is exhausted -- spots taken). The ladder
	// named the claim as the economy's first move and the draw then handed
	// the hand to a tower or a lathe nine times in ten: 1.25 mexes per
	// player in minutes 2-10 against BARb's 3.7, the spots gone to them.
	// A constructor's job; the commander keeps his leash and his draw.
	if ((gDrawLadderMex > 0) && (gDrawLadderMex < int(ranked.length()))
		&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
	{
		Want@ claim = ranked[uint(gDrawLadderMex)];
		ranked.removeAt(uint(gDrawLadderMex));
		ranked.insertAt(0, claim);
		gDrawLadderTaken = true;
		return true;
	}
	if ((gDrawLadderMex == 0) && !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)) {
		gDrawLadderTaken = true;
		return true;
	}
	if (sumV2 > 0.f) {
		uint h2 = uint(atFrame) * 2654435761 + uint(unit.id) * 40503 + salt * 97;
		h2 ^= (h2 >> 13);
		float roll2 = float(h2 % 10000) / 10000.f * sumV2;
		for (int c = 0; c <= CAT_N; ++c) {
			if (catBest[c] < 0)
				continue;
			roll2 -= wt[c];
			if (roll2 <= 0.f) {
				const int ri = catBest[c];
				// A TECH LAB IS NOT SAMPLED (his 09-17 ruling: T2 only once
				// it can be afforded, and not late). Its price carries the
				// lab, its first constructor and the time income needs to
				// pay for both; a lottery re-rolled every election buys any
				// commitment eventually. It wins when it is the best thing
				// to do, which is what keeps it from being late.
				if ((ri > 0) && (ranked[ri].kind == WK_TECH) && (ri != gDrawLadderTech)) {
					if (ai.frame >= gTechNotDrawnAt) {
						gTechNotDrawnAt = ai.frame + 60 * SECOND;
						AiLog("apex: tech-not-drawn t=" + ai.teamId + " "
							+ ((ranked[ri].def is null) ? "?" : ranked[ri].def.GetName())
							+ " v=" + formatFloat(ranked[ri].value, "", 0, 2)
							+ " lead=" + formatFloat(ranked[0].value, "", 0, 2));
					}
					break;
				}
				if (ri > 0) {
					Want@ drawn = ranked[ri];
					ranked.removeAt(uint(ri));
					ranked.insertAt(0, drawn);
					didDraw = true;   // the hoist above did not survive the draw
				}
				break;
			}
		}
	}
	return didDraw;
}

int gStallRefuseLogAt = 0;

bool EcoOnly()
{
	return ai.GetTunable("apex_eco_only", TUNE_ECO_ONLY) > 0.f;
}

IUnitTask@ Decide(CCircuitUnit@ unit)
{
	if ((unit is null) || !unit.circuitDef.IsBuilder() || !unit.circuitDef.IsMobile())
		return null;
	gElecCallUs = 0.0;
	// A unit whose task keeps dying young re-enters every frame; 2s per
	// unit caps the global decide rate without touching legit elections
	// (a successful decide holds its task far longer than this).
	// A builder that is part-way through assembling its want set is EXEMPT: the
	// gate is there to cap re-elections, and applying it to a resumption would
	// stretch every sliced election by two seconds a step -- "delays of more
	// than a second are unacceptable" (apexearth, maketask.as).
	if (!ElecPending(unit)
		&& (int(unit.id) >= 0) && (int(unit.id) < int(gLastDecideAt.length()))) {
		if (ai.frame - gLastDecideAt[int(unit.id)] < 2 * SECOND) {
			if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
				++Builder::gComBounce;   // a task that died within 2 s of being handed out
			++gDecBounce;
			return null;
		}
		gLastDecideAt[int(unit.id)] = ai.frame;
	}
	{ double _t = Perf::T0(); WorkerSeen(unit); Perf::Add("dec.worker", _t); }
	{ double _t = Perf::T0(); LedgerSweep(); Perf::Add("dec.sweep", _t); }
	{ double _t = Perf::T0(); RiskDiag(); Perf::Add("dec.riskdiag", _t); }
	// STAYING ALIVE OUTRANKS THE JOB, and it is asked BEFORE the
	// finish-what's-started return below -- a commander with progress on a
	// frame would otherwise never reach this at all, which is exactly the
	// state he dies in (apexearth, watching: "he did *nothing* to protect
	// himself").
	{
		const double _tCs = Perf::T0();
		IUnitTask@ safe = CommanderSafety(unit);
		Perf::Add("dec.comsafe", _tCs);
		if (safe !is null)
			return safe;
	}
	// SEEN THEIR AIR WITH NOTHING THAT SHOOTS UP INTERRUPTS THE JOB
	// (apexearth: "it should interrupt what we are currently doing as a
	// builder. AA coverage is cheap and easy"). The panic below only reorders
	// an election, and a builder with progress on a frame returns under this
	// and never has one. Ends the moment the first tower stands.
	bool aaEmerg = !ProtAnyComing(PROT_AA)
			&& (Military::AirSeenEver() > 0.f);
	if (aaEmerg) {
		const bool stale = (ai.frame - gAaClaimAt) > 20 * SECOND;
		if ((gAaClaim == int(unit.id)) || (gAaClaim < 0) || stale) {
			gAaClaim = int(unit.id);
			gAaClaimAt = ai.frame;
		} else {
			aaEmerg = false;   // someone else is already on it
		}
	} else {
		gAaClaim = -1;
	}
	// (The in-election "finish what's started" hold that lived here was
	// UNREACHABLE: MakeTaskInner returns any held BUILDER task before Decide
	// is ever called, so maketask.as's hold -- at ANY progress -- is the live
	// rule. The aaEmerg claim above stays: it serializes which FREE builder
	// answers the panic.)

	// GO BACK FOR WHAT THE STALL MADE YOU DROP. The one thing maketask.as's
	// hold cannot cover: the stall interrupt ABORTED the task, so there is no
	// held task to return and this unit arrives here free, with a frame of its
	// own standing somewhere. Nothing else asks -- the market re-prices every
	// want from scratch and the plant it left already reads as committed, so
	// the next election buys an LLT beside him instead (apexearth: "instead of
	// going back to the factory"). Below the safety rungs, and below the AA
	// panic, which is an interrupt in its own right.
	if (!aaEmerg) {
		const double _tDb = Perf::T0();
		IUnitTask@ debt = StallDebtPay(unit);
		Perf::Add("dec.stalldebt", _tDb);
		if (debt !is null)
			return debt;
	}

	// THE SLICED ELECTION -- see the budget header above. The set is assembled a
	// few proposers at a time and Decide holds the builder at null until it is
	// whole; the finish below then runs atomically on the completed set. A
	// builder with no id we can key on (there is no such thing, but the array
	// is bounded) assembles in one call, exactly as the stack used to.
	ElecLog();
	int elecAt = ai.frame;
	array<Want@>@ wants;
	if (!ElecIdOk(unit)) {
		array<Want@> whole;
		for (int s = 0; s < ELEC_STEPS - 1; ++s)
			whole.insertLast(ProposeStep(s, unit));
		@wants = whole;
	} else {
		Elec@ st = ElecOpen(unit);
		ElecPump();   // oldest first, and this set is in the queue
		if ((st.step < ELEC_STEPS - 1) || !ElecAfford(ELEC_STEPS - 1)) {
			if (st.step < ELEC_STEPS - 1)
				++gElecPartial;
			else
				++gElecHeld;
			Perf::Note("dec.partial");
			return null;
		}
		gMexOpen = st.sMexOpen;    // the finish prices against SpotM() too
		gLastSpotM = st.sSpotM;
		@wants = st.wants;
		elecAt = st.startFrame;
		if (ai.frame - elecAt > gElecWorstWait)
			gElecWorstWait = ai.frame - elecAt;   // the number to read: assembly latency
		ElecDrop(int(unit.id));
		++gElecDone;
	}
	gElecFinishing = true;   // maketask.as charges the finish through ElecSpendRest
	// EXPOSURE IS A COST THE ASSET ITSELF PAYS. A want's return is reduced by
	// the rate at which the thing is expected to be destroyed where it would
	// stand, so an expensive structure on uninsured ground prices itself down
	// -- and either moves somewhere covered, waits for the cover to be worth
	// buying first, or stops being worth building at all. Without this the
	// two decisions are independent and a fusion can win every auction while
	// nothing on the map protects it (apexearth). Same law decide.as already
	// applies to the commander, generalized past him.
	// Protect wants are exempt from the STANDING charge: their gain is already
	// the loss they prevent, so charging them again would price a turret for
	// its own exposure twice.
	//
	// They are NOT exempt from the CONSTRUCTION charge below. A nanoframe has
	// no weapon and a sliver of its final hitpoints, so the gain above -- which
	// assumes the thing ends up standing -- is only collected if the build
	// survives. HazardAt is a loss rate over apex_exposed_loss_s, so the same
	// rate across the build's own duration is what separates a turret that
	// lands in forty seconds from one that spends minutes as a frame. This is
	// the whole difference between a 450m HLT and a 1300m Agitator, and
	// nothing priced it: measured over 54 games, 94% of the Agitators we lost
	// and 100% of the fusions died unfinished, 27% of all metal we ever lost.
	const double _tExpose = Perf::T0();
	const float lossH = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
	const float frameK = ai.GetTunable("apex_frame_risk", TUNE_FRAME_RISK);
	for (uint i = 0; i < wants.length(); ++i) {
		Want@ c = wants[i];
		if ((c is null) || (c.value <= 0.f) || (c.def is null))
			continue;
		if (c.def.IsMobile() || !OnMap(c.pos))
			continue;
		// A def we RETIRED ON PURPOSE is not re-bought at full price while
		// the window runs -- applied here so every buyer (plant, tech, super,
		// protect, energy) honors the same memory, not only the one proposer
		// that happened to learn it.
		if (c.kind != WK_RECLAIM) {
			const float rm = RetiredDefMul(int(c.def.id));
			if (rm < 1.f) {
				c.gain *= rm;
				c.value = (c.gain > 0.f) ? (c.gain / (c.mCost + c.tCost)) : 0.f;
				if (c.value <= 0.f)
					continue;
			}
		}
		// An unset pos is the origin, and the origin reads as maximally
		// exposed ground -- charging it would quietly suppress every want
		// that forgot to name a site.
		if ((c.pos.x < 1.f) && (c.pos.z < 1.f))
			continue;
		const float exposed = ExpectedLossAt(c.pos, c.def.costM);
		if (exposed <= 0.f)
			continue;
		float charge = (c.kind == WK_PROTECT) ? 0.f : exposed;
		if ((frameK > 0.f) && (c.buildSec > 0.f) && (lossH > 1.f))
			charge += exposed * frameK * (c.buildSec / lossH);
		if (charge <= 0.f)
			continue;
		c.gain -= charge;
		c.value = (c.gain > 0.f) ? (c.gain / (c.mCost + c.tCost)) : 0.f;
	}
	Perf::Add("dec.expose", _tExpose);
	// Highest value first; a want the executor refuses (ground taken, request
	// standing, join out of reach) falls out and the runner-up is tried --
	// a builder never idles while a positive want remains executable.
	const double _tRank = Perf::T0();
	array<Want@> ranked;
	for (uint i = 0; i < wants.length(); ++i) {
		Want@ c = wants[i];
		if ((c is null) || (c.value <= 0.f))
			continue;
		if (RecentlyRefused(unit, c)) {
			++gRefDropped;
			if (ai.frame >= gNextRefLog) {
				gNextRefLog = ai.frame + 30 * SECOND;
				AiLog("apex: refused-memo t=" + ai.teamId + " " + unit.circuitDef.GetName()
					+ " #" + unit.id + " drops " + KindName(c.kind) + ":"
					+ ((c.def is null) ? "-" : c.def.GetName())
					+ " at=" + int(c.pos.x) + "," + int(c.pos.z)
					+ " dropped=" + gRefDropped);
			}
			continue;
		}
		// This instance's interest in the category (Persona): the strategic
		// wants carry theirs from their own pricing.
		if (c.kind != WK_SUPER)
			c.value *= Persona::CategoryMult(CategoryOf(c.kind));
		// THE BUDGET IS A LEVER, not a log. BudgetMult is target/actual, bounded
		// 0.35..2, computed every frame for nobody -- apexearth 2026-09-22: "if
		// we already see that our build power is high, then we do it even less
		// ... and 0.38 divided by 0.1 amplifies that one -- we whip things back
		// into shape". apex_budget already gates it and already reads 1.
		if (c.kind != WK_SUPER)
			c.value *= BudgetCatMult(CategoryOf(c.kind));
		uint at = 0;
		while ((at < ranked.length()) && (ranked[at].value >= c.value))
			++at;
		ranked.insertAt(at, c);
	}
	Perf::Add("dec.rank", _tRank);
	// THE SPLIT OF NEED, read off the full list before any hoist or role.
	if (ranked.length() > 0) {
		array<int> cbC;
		array<float> wtC;
		ConRoleCensus(wtC, DrawWeights(ranked, cbC, wtC));
		ConRoleLog();
	}
	// THE ETA LAYER. Shadow-logs always; re-ranks the economic categories only
	// while apex_eta is on. Above the panics on purpose -- those are safety and
	// keep their hoist; this only decides which economy want represents its
	// category in the draw below.
	{
		const double _tEta = Perf::T0();
		EtaLog(ranked, unit);
		Perf::Add("dec.eta", _tEta);
	}
	// THEIR AIR WITH NOTHING THAT SHOOTS UP IS AN EMERGENCY, NOT A BID.
	// apexearth: "when enemy starts bombing us and we have 0 AA I expect the
	// very next thing we build to be AA" -- and, later, not to wait for the
	// bombing: seeing their air is the trigger. While it holds, the airdef
	// want skips the lottery rather than taking a proportional share of it.
	// It stops the instant the first tower stands.
	const double _tPanic = Perf::T0();
	bool aaPanic = false;
	// What put ranked[0] there -- logged on the decide line, because a hoist
	// and a draw look identical from outside and were read as a broken draw.
	string why = "draw";
	// A WALLED-IN UNIT CAN REACH NOTHING BUT ITS WALL. The pen reclaim
	// held v=143-148 and still lost the commander's election to the stall
	// hoist twice and to the draw once (gate, Frozen Ford s5): two minutes
	// in the pocket with the cure priced and waiting.
	const Id penWall = Military::PenWallOf(unit.id);
	if (penWall != 0) {
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if ((ranked[ri].kind != WK_RECLAIM) || (ranked[ri].target is null)
					|| (ranked[ri].target.id != penWall))
				continue;
			if (ri > 0) {
				Want@ pw = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, pw);
			}
			aaPanic = true;
			why = "penned";
			break;
		}
	}
	if (aaEmerg) {
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if (ranked[ri].kind != WK_AIRDEF)
				continue;
			if (ri > 0) {
				Want@ aa = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, aa);
			}
			aaPanic = true;
			why = "aa";
			if (ai.frame >= gNextAaPanicLog) {
				gNextAaPanicLog = ai.frame + 15 * SECOND;
				AiLog("apex: AA PANIC -- seen "
					+ formatFloat(Military::AirSeenEver(), "", 0, 0)
					+ " metal of enemy air with zero AA standing; "
					+ ((ranked[0].def is null) ? "?" : ranked[0].def.GetName())
					+ " jumps the queue");
			}
			break;
		}
	}
	// A HOME WITH NOTHING DEFENDING IT IS ALSO AN EMERGENCY (apexearth: "I'd
	// also argue a home base with 0 defense on a small 1v1 map vs barb ai is an
	// emergency"). Same shape as the AA panic: both halves measured -- we own
	// zero ground defence AND something is actually killing our structures --
	// so it cannot fire on a hunch and it ends the moment the first tower
	// stands. Ranked ahead of the lottery rather than given a share of it.
	// ...and ONE CLAIMANT AT A TIME, exactly like the AA claim above it: with
	// every electing builder hoisted, a stuck builder re-bought the tower each
	// re-election and each new task killed the last -- 117 armguard tasks, 115
	// same-frame aborts, 2 built, in one watched 8v8.
	bool defClaimOk = true;
	// One read for both halves: the claim and the hoist below asked the
	// identical question, and LossRateAt is a risk-field read, not a field
	// access -- it was taken twice per election, three times when it fired.
	float homeLoss = 0.f;
	bool defEmerg = false;
	if (!aaPanic) {
		// The sensor is the whole field (LossRateAt(home) misses outlying
		// mexes); the exit is the first tower, standing or ordered. "Below
		// DefenceTarget" as the exit is never reached while the economy
		// grows, so the hoist ran all game buying v=0.00 towers -- the
		// shortfall is the priced market's job, and the loss field already
		// prices it at the sites that are dying.
		homeLoss = BleedM();
		defEmerg = (homeLoss > 0.f)
				&& (DefenceValue() <= 0.f) && (DefenceInFlightM() <= 0.f);
	}
	if (defEmerg) {
		const bool dStale = (ai.frame - gDefClaimAt) > 20 * SECOND;
		if ((gDefClaim == int(unit.id)) || (gDefClaim < 0) || dStale) {
			gDefClaim = int(unit.id);
			gDefClaimAt = ai.frame;
		} else {
			defClaimOk = false;
		}
	} else {
		gDefClaim = -1;
	}
	if (defEmerg && defClaimOk) {
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if (ranked[ri].kind != WK_PROTECT)
				continue;
			if (ri > 0) {
				Want@ dw = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, dw);
			}
			aaPanic = true;   // reuse the skip-the-lottery flag
			why = "defpanic";
			if (ai.frame >= gNextDefPanicLog) {
				gNextDefPanicLog = ai.frame + 15 * SECOND;
				AiLog("apex: DEF PANIC -- losing "
					+ formatFloat(homeLoss, "", 0, 2)
					+ " m/s of our own structures with zero defence standing or ordered; "
					+ ((ranked[0].def is null) ? "?" : ranked[0].def.GetName())
					+ " jumps the queue");
			}
			break;
		}
	}
	// A HARD E-STALL IS NOT A LOTTERY (apexearth: "if we are e-stalling...
	// MAKE A BASIC SOLAR. There's no question about it"). The stall interrupt
	// aborts a builder on the strength of a dry-run that says his top want is
	// energy -- and then the roulette re-rolled the freed builder onto
	// whatever else held a ticket: measured, a commander pulled off a
	// nearly-finished mex walk who then bought an armllt at home six times in
	// a row while the stall kept re-interrupting him (the tower is not an
	// ENERGY task, so it was never exempt). Mid-HARD-stall the energy want
	// takes the election outright; the roulette resumes when the bank does.
	//
	// ONE SOLAR ANSWERS "MAKE A BASIC SOLAR". With a generator already on
	// the way the question is answered, and hoisting every further builder
	// onto the same site adds hands to a job that is waiting on metal, not
	// on lathes: measured, 14 of 17 opening elections were this hoist, all of
	// them joining one solar, while three mexes stood without a gun. Energy
	// keeps its ticket in the draw below like anything else.
	// ...AND ALWAYS FOR A BUILDER THE INTERRUPT JUST FREED: it was taken off a
	// standing frame on the promise of this answer, so handing it back to the
	// draw makes the abort pure loss.
	const bool owedE = StallFreedOwed(unit);
	// ONE SOLAR USED TO CALL OFF THE EMERGENCY. The gate was
	// `EMakeInFlight() <= 0`, and EMakeInFlight is energy-per-second on the way,
	// not a count -- so the instant ONE builder started a 20 e/s solar the hoist
	// switched off for every other builder, and they all went back to mexes
	// while the stall continued. apexearth, watching Supreme Isthmus 2026-09-08:
	// "I just see a lot of e-stalling and only 1 con is making any effort to fix
	// that. All it'd take to 3-4x our energy growth would be the commander
	// focusing on improving that situation for a few minutes."
	//
	// Measured in that game at minute 6: income 226 e/s against a pull of 313,
	// bank 25 of 1500, and the builders held 17 mex tasks against 7 energy ones
	// -- and a mex makes the stall WORSE, because it costs energy to build and
	// then adds metal income that needs energy to spend.
	//
	// Keep hoisting while what is ORDERED still does not cover the deficit, and
	// stop by itself when it does. The deficit, not EnergyShortOfOrdered: that
	// predicate is behind apex_e_parallel (0), so it read false for every
	// builder and the hoist fired only for the ones the interrupt had freed.
	// The interrupt's own bar ("above 400 we probably don't need it"): one
	// bar for both by-fiat answers to a stall.
	// ...except with the metal bank full: then the stall is not a transient
	// in the pull, it is income being thrown away (apexearth, watching:
	// "overflowing metal like crazy... we should just have loads of guys
	// making solars").
	// No income bar: the deficit is the fleet's ask against what we make,
	// and it was 1,950 e/s at 773 e/s of income with the hoist switched off
	// by the 400 bar while the metal bank sat full for twelve minutes
	// (Isthmus seed 13, 2026-09-08). Above the bar the market's energy price
	// lost 6 draws in 12 minutes to 37 radars and 36 mexes.
	const bool hoistWorth = true;
	if (!aaPanic && hoistWorth && HardEStall() && ((EnergyDeficitNowE() > 0.f) || owedE)) {
		// WHAT IS ORDERED COVERS IT ONCE FED: then the stall wants hands on
		// the crawling frame, not another frame beside it. Watched on Comet
		// Catcher (2026-09-15): the hoist put up a second and a third fusion
		// while the first crawled, and all three then starved on one moho.
		const bool ordered = (EnergyDeficitNowE() - EMakeOrderedE() <= 0.f);
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if (ordered) {
				if (ranked[ri].kind != WK_ASSIST)
					continue;
			} else if (ranked[ri].kind != WK_ENERGY) {
				// "MAKE A BASIC SOLAR" -- not a 900-metal geothermal
				// (watched on Altored: the hoist sent the opening's cons to
				// the vents while the mexes stood unclaimed).
				continue;
			}
			if (ri > 0) {
				Want@ ew = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, ew);
			}
			aaPanic = true;   // reuse the skip-the-lottery flag
			why = ordered ? "estall-hands" : "estall";
			StallFreedClear(unit);
			break;
		}
	}
	if ((why != "estall") && (ai.frame >= gNextHoistLog) && aiEconomyMgr.isEnergyEmpty) {
		gNextHoistLog = ai.frame + 15 * SECOND;
		AiLog("apex: nohoist t=" + ai.teamId + " " + unit.circuitDef.GetName()
			+ " aa=" + (aaPanic ? 1 : 0) + " worth=" + (hoistWorth ? 1 : 0)
			+ " hard=" + (HardEStall() ? 1 : 0)
			+ " deficit=" + int(EnergyDeficitE())
			+ " mFull=" + (aiEconomyMgr.isMetalFull ? 1 : 0)
			+ " eInc=" + int(aiEconomyMgr.energy.income)
			+ " ranked=" + ranked.length());
	}
	// AFFORDABILITY IS THE WHOLE TEST FOR A STRATEGIC BUILD. apexearth: "it is
	// more of a 'if I can afford this, I'll insert it as a want so we make
	// one'." A gantry or a silo returns destruction rather than metal/s, so it
	// can never out-price a mex per metal and a proportional ticket would draw
	// it once a game at best -- which is the state he is reporting. Its own
	// proposer already refuses unless the economy makes the whole bill inside
	// apex_super_afford_s, only one strategic frame stands at a time, and the
	// counts rise with income, so what this skips is the lottery, not a budget.
	// No converter hoist: tried 2026-09-16 and measured worse (commit
	// 28504349) -- the price wins the draw once the ladder's ticket is its
	// own (eta.as EtaEcoWeight). The flag stays so the chain below reads.
	const bool convertPush = false;
	bool superPush = false;
	if (!aaPanic && !convertPush && (ai.GetTunable("apex_super_push", TUNE_SUPER_PUSH) > 0.f)) {
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if (ranked[ri].kind != WK_SUPER)
				continue;
			// An anti-nuke against no silo seen is insurance, priced in the
			// draw like the rest; the push is for the weapon itself. His
			// Comet 1v1: the third T2 con hoisted to an anti-nuke at 13 min,
			// metal-starved, no enemy silo, the enemy at 250 m/s.
			if ((ranked[ri].def !is null) && Catalog::gAntiNuke[int(ranked[ri].def.id)]
				&& (Brain::EnemyNukeSilos() <= 0))
				continue;
			if (ri > 0) {
				Want@ sw = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, sw);
			}
			superPush = true;
			why = "super";
			AiLog("apex: super-push t=" + ai.teamId + " "
				+ SuperName(ranked[0].spotId) + ":"
				+ ((ranked[0].def is null) ? "?" : ranked[0].def.GetName())
				+ " by " + unit.circuitDef.GetName() + " #" + unit.id);
			break;
		}
	}
	// COVER WHAT YOU JUST BUILT. A constructor that has just finished a mex is
	// standing on the one piece of ground whose tower costs no walk at all, and
	// the draw below would still send it somewhere else half the time. Every
	// condition here has to hold: the want is ground defence, its site is a mex
	// of ours, that mex is still under the cover floor, and the builder is
	// already within the tower's own reach of it. So this cannot pull defence
	// forward in general -- it closes exactly the gap between building a thing
	// and protecting it.
	bool coverPush = false;
	// ...ONCE A PLANT EXISTS. Before the lab the jump put a light tower
	// ahead of the factory (mex, mex, mex, tower, solar, lab -- and in one
	// game tower after tower with no factory in 17 minutes). His order:
	// "mexes/energy -> T1 lab -> more energy -> 1 or 2 turrets to guard";
	// the commander's first-gun rule below covers the lab the moment it is
	// ordered.
	// PlantFramed walks the commitment ledger; the tunable is a map lookup, so
	// it is asked first.
	if (!aaPanic && !superPush && !convertPush
		&& (ai.GetTunable("apex_cover_push", TUNE_COVER_PUSH) > 0.f)
		&& PlantFramed())
	{
		const float floorWave = MexCoverFloorM()
				* ai.GetTunable("apex_def_trade", TUNE_DEF_TRADE);
		const float near = Brain::LightTowerRange();
		const float pushAff = ai.GetTunable("apex_cover_push_s", TUNE_COVER_PUSH_S);
		const float pushCap = EcoPowerM() * pushAff;
		const AIFloat3 uAt = unit.GetPos(ai.frame);
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			Want@ cw = ranked[ri];
			if ((cw.kind != WK_PROTECT) || (cw.spotId != PROT_DEF))
				continue;
			// REVERTED. Retargeting the want to the nearest mex in reach was
			// mine tonight and it was never shown to help -- mex coverage went
			// 83% to 85%, inside the run-to-run spread -- while it demonstrably
			// hurt: the same mex is the nearest one on every election, so the
			// jump kept firing at it and the commander stacked SIX turrets on
			// one extractor (apexearth, watching: "he makes like 6 mexes this
			// game... finally he decides to defend one and he makes 6 turrets").
			//
			// The queue jump goes back to what it was: it promotes a defence
			// want that is ALREADY sited at a mex, and does not invent one.
			// That leaves the real problem where it belongs -- the wall
			// generator does not offer sites at the things we build -- instead
			// of papering over it with a rule that spends without a bound.
			// THE GUN GOES ON THE MEX THE HAND IS STANDING AT (apexearth
			// 2026-09-17: "focusing our defenses right on our mexes outside
			// our bases"). The auction's best site is somewhere else more
			// often than not; the mex the builder just capped, short of the
			// guns it earns, is the site. Retargeting was tried once and
			// stacked six guns on one mex because cover counted finished
			// towers only -- the ledger test below is what makes it safe.
			{
				const AIFloat3 mexAt = NearestMex(uAt, near);
				if (OnMap(mexAt) && MexUnguardedInReach(mexAt, near))
					cw.pos = mexAt;
			}
			// THE GUN GOES WHERE THE COMMANDER STANDS when something he
			// cannot catch is circling him (apexearth 2026-09-19: "Instead
			// of him chasing them, he should just make a turret where he
			// is... as long as we've got some turret coverage on whatever
			// he's trying to build"). The ground he works is the site.
			const bool scouted = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
					&& FastFoeNear(uAt, near * 2.f,
					Catalog::gSpeed[int(unit.circuitDef.id)]);
			if (scouted && !MexUnguardedInReach(cw.pos, near))
				cw.pos = uAt;
			if ((!SiteIsMex(cw.pos) && !scouted) || (uAt.distance2D(cw.pos) > near))
				continue;
			if ((cw.def !is null) && InteriorGunSite(int(cw.def.id), cw.pos))
				continue;
			// The same exposure-scaled floor the site loop asks for -- a
			// rear mex's floor is ~zero and the jump must not out-buy it.
			const float floorHere = floorWave * MexFloorFactor(cw.pos);
			if (floorHere <= 1.f)
				continue;
			const float coverHere = CoverAt(cw.pos);
			if (coverHere >= floorHere)
				continue;
			// THE LEDGER, NOT THE FINISHED FIELD. CoverAt reads standing guns,
			// so while the first tower was a frame the jump fired again every
			// election: the commander stacked seven light towers on one mex
			// cluster in eighty seconds at cover=0 throughout (his watch,
			// 2026-09-16: "~7 turrets all made right next to each other at
			// 7m"). A gun ordered within reach of the site's mex is its gun.
			if (!MexUnguardedInReach(cw.pos, near))
				continue;
			// ...AND ONLY ONCE THE BASE CAN AFFORD IT (apexearth 2026-08-27:
			// "turrets aren't bad to have but usually thats made after we have
			// our basic base set up. mexes/energy -> T1 lab -> more energy ->
			// 1 or 2 turrets to guard", ruling that the jump should be gated
			// on economic power rather than deleted).
			//
			// This is a QUEUE JUMP, not a price -- it hands the election to a
			// want the market scored at 0.03 against a mex at 88.17, measured
			// -- so at opening income it spends the whole economy on sentries
			// before there is an economy. Affordability is the tower's cost
			// against what we earn: at 4 metal/s a 90-metal LLT is twenty
			// seconds of everything we make, at 20 it is four. The jump waits
			// until that bill is small enough to be worth overriding the
			// auction for; below it the tower still competes on price like
			// anything else, so nothing is forbidden.
			// The bill in one currency: a light tower is 85 metal and 680
			// energy, and four of them went up through a hard stall on the
			// metal half alone.
			if (cw.def !is null) {
				const int cd = int(cw.def.id);
				const float bill = Catalog::gCostM[cd] + Catalog::gCostE[cd]
						* EPriceCostAt(cw.buildSec, Catalog::gCostE[cd]);
				if (bill > pushCap)
					continue;
			}
			if (ri > 0) {
				ranked.removeAt(ri);
				ranked.insertAt(0, cw);
			}
			// EXEMPT FROM THE DRAW AGAIN, for the FIRST gun only. The jump
			// was cut back to a hoist when it bought a tower on every claim
			// (96 pushes in one game, metal 28 of 265 elections) -- but that
			// was the cover floor asking for more guns while cover stayed
			// under it. A site is now offered only while its mex has NO gun
			// ordered or standing (MexUnguardedInReach), so the most this can
			// buy is one light tower per extractor, which is the ask
			// (apexearth 2026-09-02: "1 sentry turret guarding each of our
			// mexes at least"). Left to the draw, that gun lost to the next
			// mex about half the time and mexes stood naked past minute six.
			// The affordability bar above still holds it back at opening
			// income.
			why = "cover";
			coverPush = true;
			AiLog("apex: cover-push t=" + ai.teamId + " "
				+ ((ranked[0].def is null) ? "?" : ranked[0].def.GetName())
				+ " by " + unit.circuitDef.GetName() + " #" + unit.id
				+ " walk=" + int(uAt.distance2D(ranked[0].pos))
				+ " cover=" + int(coverHere)
				+ "/" + int(floorWave));
			break;
		}
	}
	// PROPORTIONAL DRAW OVER CATEGORIES, argmax inside one (apexearth:
	// "think about eco related things by category... then we pick the
	// highest value energy"). The draw still exists -- winner-takes-all
	// starved every want that never ranked #1 (team 3 bought nanos at
	// v=20-275 for 8 minutes while the T2 lab bid 16.7 once and never won).
	// What changed is WHO gets a ticket: energy/geo/convert/store used to
	// draw four times per election against extraction's two, which is how
	// 672 wind turbines were bought against 1 moho upgrade (measured). One
	// question, one ticket, weighted by that question's best answer.
	// Rebuild is a price, not a rule: no hoist of the spot that just died.
	Perf::Add("dec.panic", _tPanic);
	// A ROLED HAND ELECTS INSIDE ITS CATEGORY -- see roles.as. Below the
	// panics, above the draw.
	// BARb's factory floor outranks the draw: a nano want sourced from a
	// factory short of its caretakers is taken, not sampled (apexearth
	// 2026-09-11: "it should be high priority").
	bool floorPush = false;
	if (!aaPanic && !superPush && !coverPush && !convertPush) {
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if ((ranked[ri].kind != WK_NANO) || (ranked[ri].spotId != NS_FLOOR))
				continue;
			if (ri > 0) {
				Want@ fw = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, fw);
			}
			floorPush = true;
			why = "nanofloor";
			break;
		}
	}
	// THE ONLY ADVANCED HAND UPGRADES A MEX FIRST (his rule, 2026-09-15:
	// "after you make the first advanced constructor... it should be to make
	// an advanced metal extractor, and if it's not, then something's
	// wrong"). The draw had it start the reactor at v=15 over the moho at
	// v=17 -- a 60-second payback against a ten-minute one, and no other
	// hand can build either. While no second advanced hand stands, a mexup
	// in the list is taken, not drawn.
	if (!aaPanic && !superPush && !coverPush && !floorPush && !convertPush && (ranked.length() > 1)
		&& SoleAdvancedHand(unit)) {
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if (ranked[ri].kind != WK_MEXUP)
				continue;
			if (ri > 0) {
				Want@ mw = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, mw);
			}
			floorPush = true;
			why = "firstT2";
			break;
		}
	}
	// THE T2 SWITCH'S OWN PURPOSE, TAKEN AND NOT SAMPLED. The switch names
	// fusions as what it is for and then only removes army from the target;
	// the freed metal went to the draw, which bought wind 48 times to the
	// fusion's 3 while the switch read NOFUS from frame 18.
	if (!aaPanic && !superPush && !coverPush && !floorPush && !convertPush
		&& (ranked.length() > 1)
		&& (ai.GetTunable("apex_t2_fusion_pull", TUNE_T2_FUSION_PULL) > 0.f)
		&& T2WantsFusion()) {
		int fusSeen = 0;
		int fusEnergy = 0;
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			Want@ fw = ranked[ri];
			if ((fw.kind != WK_ENERGY) || (fw.def is null))
				continue;
			++fusEnergy;
			const int fd = int(fw.def.id);
			if (!AdvancedOnlyDef(fd) || (Catalog::gMakeE[fd] <= 0.f))
				continue;
			++fusSeen;
			if (ri > 0) {
				ranked.removeAt(ri);
				ranked.insertAt(0, fw);
			}
			floorPush = true;
			why = "t2fusion";
			break;
		}
		if ((why != "t2fusion") && (ai.frame >= gNextFusDiag)) {
			gNextFusDiag = ai.frame + 15 * SECOND;
			AiLog(Factory::T() + "apex: t2fusion-miss " + unit.circuitDef.GetName()
				+ " ranked=" + ranked.length()
				+ " energyWants=" + fusEnergy
				+ " advGenWants=" + fusSeen);
		}
	}
	bool roled = false;
	if (!aaPanic && !superPush && !coverPush && !floorPush && !convertPush && (ranked.length() > 1)
		&& (ai.GetTunable("apex_role_share", TUNE_ROLE_SHARE) > 0.f)) {
		roled = ConRoleApply(unit, ranked);
		if (roled)
			why = "role";
	}
	// METAL FIRST: while the unlock is starved of feed, no hand opens
	// another sink -- four Dragon's Claws and an air plant went up beside
	// a T2 plant crawling at share 0.77. Metal, its energy, reclaim and
	// help stay; the panics above have already had their say.
	if (!aaPanic && !superPush && !coverPush && !floorPush && !convertPush && !roled
		&& (ranked.length() > 1) && MetalPathStarved())
	{
		for (uint ri = 0; ri < ranked.length(); ) {
			const int k = ranked[ri].kind;
			if ((k == WK_MEX) || (k == WK_MEXUP) || (k == WK_TECH) || (k == WK_ENERGY)
				|| (k == WK_CONVERT) || (k == WK_RECLAIM) || (k == WK_ASSIST) || (k == WK_GEO)) {
				++ri;
				continue;
			}
			ranked.removeAt(ri);
			++gMetalFirstCut;
		}
	}
	// METAL FIRST: a free hand joins the unlock in flight (want_assist.as).
	// Not over its own metal work -- a mex, an upgrade or the plant itself.
	if (!aaPanic && !superPush && !coverPush && !floorPush && !convertPush && !roled
		&& (ranked.length() > 0) && (ranked[0].kind != WK_MEX)
		&& (ranked[0].kind != WK_MEXUP) && (ranked[0].kind != WK_TECH))
	{
		Want@ ua = ProposeUnlockAssist(unit);
		if ((ua !is null) && (ua.kind == WK_ASSIST)) {
			ranked.insertAt(0, ua);
			floorPush = true;
			why = "metalfirst";
		}
	}
	// THE FIRST PLANT IS NOT A DICE ROLL. The draw keeps runners-up alive
	// over many elections; the one election that unlocks the con floor and
	// every unit lost the roll twice at 60:40 and the lab came a minute
	// after theirs, into an energy stall. While no plant stands or is
	// ordered, a plant anywhere in the list is taken: every target holds
	// army, and no army arrives through a tower, so the plant's ETA to any
	// of them is the shortest whatever the per-instant ranking says. Only
	// the panics above outrank it.
	bool firstPlant = false;
	if (!aaPanic && !superPush && !coverPush && (ranked.length() > 0)
		&& (Factory::gFacUnits.length() == 0) && !AnyPlantInFlight())
	{
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if (ranked[ri].kind != WK_PLANT)
				continue;
			if (ri > 0) {
				Want@ pw = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, pw);
			}
			firstPlant = true;
			why = "firstplant";
			break;
		}
	}
	const double _tDraw = Perf::T0();
	if ((ranked.length() > 1) && !aaPanic && !superPush && !coverPush && !floorPush && !roled && !convertPush && !firstPlant)
		if (CategoryDraw(unit, ranked, 0, elecAt))
			why = gDrawLadderTaken ? "ladder" : "draw";
	Perf::Add("dec.draw", _tDraw);
	Want@ top = (ranked.length() > 0) ? ranked[0] : null;
	Want@ next = (ranked.length() > 1) ? ranked[1] : null;
	// Only an emergency takes a hand off a job it is on: the stall, the
	// air and defence panics, the commander's first gun. The floors and
	// roles wait for a free hand.
	// The stall's FIRST answer (a generator ordered) is worth a hand off
	// its walk; the hands that follow to lathe it are not -- once make is
	// ordered every hand in the base was pulled off its mex walk to assist
	// two solars (42 stall solars in eight minutes, seven mexes built).
	bool emergency = (why == "estall") || (why == "aa")
			|| (why == "defpanic") || (why == "penned") || (why == "cover");
	// METAL FIRST (apexearth 2026-09-19: "focus everything on the thing
	// that gets you more metal"): the stall's answer does not take a hand
	// off a mex upgrade -- the first advanced con left its first moho for
	// a fusion at v=1 over v=16, and the moho came from the third con.
	if ((why == "estall") && (top !is null)) {
		const int uidm = int(unit.id);
		if ((uidm >= 0) && (uidm < int(gIncTask.length())) && (gIncTask[uidm] !is null)
			&& !gIncTask[uidm].IsDead()
			&& (gIncTask[uidm].GetBuildType() == Task::BuildType::MEXUP))
			emergency = false;
	}
	if (!emergency && (top !is null)) {
		const int uidk = int(unit.id);
		if ((uidk >= 0) && (uidk < int(gIncTask.length())) && (gIncTask[uidk] !is null)) {
			IUnitTask@ inc = gIncTask[uidk];
			if (inc.IsDead()) {
				@gIncTask[uidk] = null;
			} else {
				// En route or at the frame alike: a hand with a lab nine
				// tenths up was drawn off it to a mex (his watch). A draw
				// is not new information either: the election that took the
				// job saw the same categories, and a value is a RATE, so a
				// nano always out-rates the plant it would abandon (the T2
				// vehicle plant left 5 s after the order, his Isthmus game).
				const AIFloat3 ip = inc.GetBuildPos();
				// A hand the peel (or any RemoveUnit) took off this job is
				// not on it: handing it back re-attached it to be peeled
				// again, a full election per cycle and never a new job.
				bool onCrew = false;
				array<CCircuitUnit@>@ crew = inc.GetUnits();
				for (uint ci = 0; (crew !is null) && (ci < crew.length()); ++ci) {
					if ((crew[ci] !is null) && (crew[ci].id == unit.id)) {
						onCrew = true;
						break;
					}
				}
				if (!onCrew) {
					@gIncTask[uidk] = null;
					++gOffCrewMin;
				} else if (OnMap(ip) && !Builder::SiteHot(ip)) {
					++gKeepJob;
					++gKeepMin;
					if (ai.frame >= gNextKeepLog) {
						gNextKeepLog = ai.frame + 30 * SECOND;
						AiLog("apex: keep-job t=" + ai.teamId + " " + unit.circuitDef.GetName()
							+ " #" + unit.id + " v=" + formatFloat(gIncVal[uidk] * 1000.f, "", 0, 2)
							+ " over " + KindName(top.kind) + " v=" + formatFloat(top.value * 1000.f, "", 0, 2)
							+ " kept=" + gKeepJob);
					}
					return inc;
				}
			}
		}
	}
	// Auction dump for T2-capable builders, one per 30s, tunable-gated.
	if ((ai.GetTunable("apex_auction_diag", 0.f) > 0.f) && (ai.frame >= gNextAuctionDiag)) {
		bool t2able = false;
		const array<int>@ mm = Catalog::BuildsOf(int(unit.circuitDef.id));
		for (uint z = 0; z < mm.length(); ++z) {
			if (Catalog::gCostM[mm[z]] > 3000.f) {
				t2able = true;
				break;
			}
		}
		if (t2able) {
			gNextAuctionDiag = ai.frame + 30 * SECOND;
			string ln = "apex: auction " + unit.circuitDef.GetName() + " #" + unit.id + " |";
			for (uint z = 0; z < ranked.length(); ++z) {
				ln += " " + KindName(ranked[z].kind) + ":"
					+ ((ranked[z].def is null) ? "?" : ranked[z].def.GetName())
					+ " v=" + formatFloat(ranked[z].value * 1000.f, "", 0, 2)
					+ " (g=" + formatFloat(ranked[z].gain, "", 0, 1)
					+ " m=" + formatFloat(ranked[z].mCost, "", 0, 0)
					+ " t=" + formatFloat(ranked[z].tCost, "", 0, 0) + ")";
			}
			AiLog(ln);
		}
	}
	if (top is null) {
		if (ai.frame >= gNextIdleLog) {
			gNextIdleLog = ai.frame + 30 * SECOND;
			AiLog("apex: decide " + unit.circuitDef.GetName() + " #" + unit.id
				+ " -> floor (no positive want)");
		}
		return IdleFloor(unit, "no positive want");
	}

	gWantEmaV = (gWantEmaV <= 0.f) ? top.value
			: (0.9f * gWantEmaV + 0.1f * top.value);
	// The decide/exec lines are ~20-term concatenations that run at apex_perf=0
	// like everything else; nothing said what they cost.
	const double _tLog = Perf::T0();
	if (DecideLogOn())
		AiLog("apex: decide t=" + ai.teamId + " " + unit.circuitDef.GetName() + " #" + unit.id
			+ " -> " + CatName(CategoryOf(top.kind))
			+ "/" + KindName(top.kind) + ":" + ((top.def is null) ? "-" : top.def.GetName())
			+ " v=" + formatFloat(top.value * 1000.f, "", 0, 2)
			+ " (gain=" + formatFloat(top.gain, "", 0, 2)
			+ " m=" + formatFloat(top.mCost, "", 0, 0)
			+ " t=" + formatFloat(top.tCost, "", 0, 0) + ")"
			+ " why=" + why
			+ ((ConRoleOf(unit) >= 0) ? (" role=" + CatName(ConRoleOf(unit))) : "")
			+ ((next is null) ? " over nothing"
				: (" over " + CatName(CategoryOf(next.kind)) + "/" + KindName(next.kind)
					+ " v=" + formatFloat(next.value * 1000.f, "", 0, 2))));
	Perf::Add("dec.log", _tLog);

	// THE COMMANDER NEVER TAKES EXPOSED WORK: his death is the game, so a
	// want's exposure is a cost HE pays at game-loss scale (measured: com
	// died at 15:00 building an LLT at a naked forward mex, medium anchor
	// t000 -- the insurance priced the mex's risk and forgot the asker's).
	const bool isComm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	// ONE GUN BEFORE HE LEAVES. apexearth, four times tonight and finally in
	// one sentence: "If the com wants to walk away they should make an LLT
	// first." The opening cluster's only builder is the commander, so the
	// moment he takes a job elsewhere the lab, the solars and the first mexes
	// stand with nothing covering them -- and the panic that follows is a game
	// every time.
	//
	// The cover floor (PlantInReach, 2026-09-01) made the turret WORTH
	// building; it did not make it worth building FIRST, and measured on this
	// seed the lab went up at 0.75 min while the first LLT waited until 1.61.
	//
	// Narrow on purpose, and self-limiting: it fires only while we own NO
	// ground defence at all, and the first tower ends it -- DefenceValue turns
	// positive and ordinary pricing resumes. It is one turret, not a wall.
	// AND HE DOES NOT LEAVE UNTIL IT IS THERE. apexearth: "just refuse to
	// leave our stuff unguarded". Choosing the gun first was not enough on its
	// own -- he still walked off to the next mex while the order sat unbuilt --
	// so while the opening cluster has no gun, work OUTSIDE it is not on the
	// menu at all. The moment one tower stands, DefenceValue turns positive and
	// this whole branch stops existing.
	if (isComm && (DefenceValue() <= 0.f)) {
		for (uint i = 0; i < ranked.length(); ++i) {
			if ((ranked[i].kind != WK_PROTECT) || (ranked[i].def is null))
				continue;
			if (Catalog::gSurfT[int(ranked[i].def.id)] <= 0.01f)
				continue;   // must be a gun that shoots the ground
			// WHY IT DID NOT GET BUILT. The rule fired six times from 0.89
			// min and the LLT still did not land until 1.54 -- the DECISION
			// was never the problem, something downstream refused to place
			// it. Requests::Gate counts every refusal reason, so the deltas
			// across this one call name the gate instead of a fourth guess.
			// AT THE PLANT, NOT ON THE WALL RIM. Measured: the gun was sited
			// at 2465,3623 while the lab stood at 2112,4624 -- a kilometre in
			// front of the thing it was meant to cover, so the base stayed
			// naked and the commander walked out of position to build it. The
			// wall generator is the only site source with traffic and at
			// minute one the building rim runs through the forward mexes.
			//
			// The first gun's job is this plant. Site it beside the nearest
			// one to the commander, a step toward the enemy so it covers the
			// approach rather than hiding behind the building.
			{
				const AIFloat3 here = unit.GetPos(ai.frame);
				AIFloat3 best;
				float bestD = -1.f;
				for (uint pi = 0; pi < ComLen(); ++pi) {
					const int pd = gComDef[pi];
					if (!Catalog::ValidId(pd) || Catalog::gMobile[pd]
						|| (Catalog::gBuildsList[pd].length() == 0)
						|| (Catalog::gBuildPower[pd] <= 0.f))
						continue;
					// A plant that is only ORDERED is not there to guard, and
					// the gun would take him off it: measured, the lab's
					// order sat unplaced, the rule pulled him to a tower at
					// minute three, and the lab died unframed at minute eight.
					if (gComState[pi] == CS_ORDERED)
						continue;
					if (!OnMap(gComPos[pi]))
						continue;
					const float dd = here.distance2D(gComPos[pi]);
					if ((bestD < 0.f) || (dd < bestD)) {
						bestD = dd;
						best = gComPos[pi];
					}
				}
				// No plant yet means nothing to leave: the gun is not
				// forced ahead of the lab, and the auction prices it as
				// usual.
				if (bestD < 0.f)
					break;
				AIFloat3 at = best;
				if (Base::Ready()) {
					AIFloat3 f = Base::gFwd;
					if (Base::AxisIsRearward()) { f.x = -f.x; f.z = -f.z; }
					at.x += f.x * 220.f;
					at.z += f.z * 220.f;
				}
				if (OnMap(at))
					ranked[i].pos = ProbedSite(ranked[i].def,
							Catalog::Def(int(unit.circuitDef.id)), at);
			}
			const int g0New = Requests::gGateSeen[Requests::G_BADREQ];
			const int g0Can = Requests::gGateSeen[Requests::G_CANBUILD];
			const int g0Back = Requests::gGateSeen[Requests::G_BACKOFF];
			IUnitTask@ g = ExecuteWant(unit, ranked[i]);
			AiLog("apex: comm-first-gun t=" + ai.teamId
				+ " " + ranked[i].def.GetName()
				+ " at=" + int(ranked[i].pos.x) + "," + int(ranked[i].pos.z)
				+ " placed=" + ((g !is null) ? 1 : 0)
				+ " badreq=" + (Requests::gGateSeen[Requests::G_BADREQ] - g0New)
				+ " canbuild=" + (Requests::gGateSeen[Requests::G_CANBUILD] - g0Can)
				+ " backoff=" + (Requests::gGateSeen[Requests::G_BACKOFF] - g0Back)
				+ " posOnMap=" + (OnMap(ranked[i].pos) ? 1 : 0)
				+ " canDef=" + (unit.circuitDef.CanBuild(ranked[i].def) ? 1 : 0));
			if (g !is null)
				return g;
			break;   // could not place it; fall through rather than idle
		}
	}
	// A refused winner is removed; then his adage (2026-09-11): "if you
	// don't know what to do, make energy... or converters". The best economy
	// want left is hoisted, and only a list with none rolls the draw again --
	// falling through to ranked[1] was the value argmax, half of all
	// executions.
	const bool redraw = !aaPanic && !superPush && !coverPush && !floorPush && !roled;
	const int topKind = (ranked.length() > 0) ? ranked[0].kind : -1;
	const string topDef = ((ranked.length() > 0) && (ranked[0].def !is null))
			? ranked[0].def.GetName() : "-";
	const uint rankedN = ranked.length();
	for (uint depth = 0; ranked.length() > 0; ++depth) {
		const uint i = 0;
		bool refused = false;
		// THE COMMANDER STAYS HOME: one leash (ComFar) for the election, the
		// floor and the chase. Extraction is NOT exempt (a 0.45-value mex
		// 1900 elmo out won a draw and that walk killed him, watched
		// 2026-09-05).
		if (isComm && ComFar(ranked[i].pos)) {
			if (ai.frame >= gComFwdLogAt + 30 * SECOND) {
				gComFwdLogAt = ai.frame;
				AiLog("apex: com-fwd skip t=" + ai.teamId + " "
					+ KindName(ranked[i].kind) + " at="
					+ int(ranked[i].pos.x) + "," + int(ranked[i].pos.z)
					+ " ff=" + formatFloat(Military::ForwardFraction(ranked[i].pos), "", 0, 2)
					+ " home=" + (Builder::gHomeSet ? int(ranked[i].pos.distance2D(Builder::gHomePos)) : -1)
					+ " (sampled 30s)");
			}
			refused = true;
		}
		IUnitTask@ t = null;
		if (!refused) {
			const double _tExec = Perf::T0();
			@t = ExecuteWant(unit, ranked[i]);
			Perf::Add("exec.want", _tExec);
			// The name is built whether or not anyone is profiling, and the
			// concat plus KindName ran on every execution at apex_perf=0.
			if (Perf::On())
				Perf::Add("xk." + KindName(ranked[i].kind), _tExec);
		}
		if (t !is null) {
			// The execution just changed the counts that priced this kind --
			// every cached answer of it is stale now, whoever asked.
			MemoEvictKind(ranked[i].kind);
			// Price tag on the job, so idle hands can later rank what is in
			// flight by what the market paid for it (floor.as).
			NoteJob(t, ranked[i]);
			// What was EXECUTED, not what was drawn -- the decide line above
			// prints ranked[0] even when the executor refuses it, so audits
			// counting decides overcount every refused want. pick>0 is a
			// fallthrough past the drawn winner.
			if (DecideLogOn())
				AiLog("apex: exec t=" + ai.teamId + " " + unit.circuitDef.GetName()
					+ " #" + unit.id + " " + KindName(ranked[i].kind) + ":"
					+ ((ranked[i].def is null) ? "-" : ranked[i].def.GetName())
					+ " pick=" + depth
					+ " at=" + int(ranked[i].pos.x) + "," + int(ranked[i].pos.z));
			if ((int(unit.id) >= 0) && (int(unit.id) < int(gIncTask.length()))) {
				@gIncTask[int(unit.id)] = t;
				gIncVal[int(unit.id)] = ranked[i].value;
			}
			// A category that could not be executed is not a job this hand
			// can do: the role goes with the fall-through.
			if (roled && (CategoryOf(ranked[i].kind) != ConRoleOf(unit))) {
				NoteCategoryFell(ConRoleOf(unit));
				ConRoleForget(int(unit.id));
				++gRoleFell;
			}
			return t;
		}
		if (!refused && (uint(ranked[i].kind) < gExecFail.length()))
			++gExecFail[ranked[i].kind];
		NoteRefused(unit, ranked[i]);
		// The stall's answer refused: the interrupt that freed this builder
		// will fire again on whatever the fallthrough starts (five in 500
		// frames, watched), so the verdict is worth a line.
		if (!refused && (depth == 0) && (why == "estall") && (ai.frame >= gStallRefuseLogAt)) {
			gStallRefuseLogAt = ai.frame + 3 * SECOND;
			AiLog("apex: stall-answer refused t=" + ai.teamId + " " + unit.circuitDef.GetName()
				+ " #" + unit.id + " " + ((ranked[0].def is null) ? "-" : ranked[0].def.GetName())
				+ " verdict=" + Requests::gLastWhat);
		}
		ranked.removeAt(0);
		// Converters while energy is being thrown away, else energy: the
		// first pass took energy by price and doubled the waste (Isthmus
		// 20.7% -> 41.9%).
		const int ecoKind = (gESurplusEma > 1.f) ? WK_CONVERT : WK_ENERGY;
		int ecoAt = -1;
		for (uint e = 0; (e < ranked.length()) && (ecoAt < 0); ++e) {
			if (ranked[e].kind == ecoKind)
				ecoAt = int(e);
		}
		for (uint e = 0; (e < ranked.length()) && (ecoAt < 0); ++e) {
			if ((ranked[e].kind == WK_ENERGY) || (ranked[e].kind == WK_CONVERT))
				ecoAt = int(e);
		}
		const bool eco = (ecoAt >= 0);
		if (ecoAt > 0) {
			Want@ ew = ranked[uint(ecoAt)];
			ranked.removeAt(uint(ecoAt));
			ranked.insertAt(0, ew);
		}
		if (!eco && redraw && (ranked.length() > 1))
			CategoryDraw(unit, ranked, depth + 1, elecAt);
	}
	// EVERY RANKED WANT REFUSED. The decide line above names what ranked
	// first, NOT what got built -- so a builder can log a decision every
	// update and hold no task at all, which is what sitting on a full bank
	// looks like from the inside. Nothing else reports the fall-through.
	++gExecNone;
	if (ai.frame >= gNextExecLog) {
		gNextExecLog = ai.frame + 30 * SECOND;
		string ln = "apex: exec-refused t=" + ai.teamId
				+ " allNull=" + gExecNone + " |";
		for (uint k = 0; k < gExecFail.length(); ++k) {
			if (gExecFail[k] > 0)
				ln += " " + KindName(int(k)) + "=" + gExecFail[k];
		}
		AiLog(ln);
	}
	// The commander's refusals by name: his stills are what he watches.
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask) && (ai.frame >= gNextComRefuseLog)) {
		gNextComRefuseLog = ai.frame + 5 * SECOND;
		AiLog("apex: com-refused t=" + ai.teamId + " top=" + KindName(topKind)
			+ ":" + topDef + " verdict=" + Requests::gLastWhat
			+ " ranked=" + rankedN);
	}
	// ...and a refused election is still an idle constructor, which is the
	// exit that actually fires (measured: 472 all-refused elections in one
	// game against zero of the no-want exit above).
	if (roled) {
		NoteCategoryFell(ConRoleOf(unit));
		ConRoleForget(int(unit.id));
		++gRoleFell;
	}
	return IdleFloor(unit, "all wants refused");
}


}  // namespace Market
