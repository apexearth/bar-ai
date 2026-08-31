namespace Market {
//------------------------------------------------------------------------------
// The arbiter's builder side. Called only from Brain::Decide.
//------------------------------------------------------------------------------

int gNextIdleLog = 0;
int gNextAuctionDiag = 0;
int gNextAaPanicLog = 0;
int gNextDefPanicLog = 0;
array<int> gLastDecideAt(32001, -30000);   // per-unit-id, Spring ids cap at 32k
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
int gNextExecLog = 0;

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
const int   MEMO_TTL = 45;   // frames (1.5s); a freshness bound, not policy
// A copy this old ALWAYS recomputes, on its own bounded budget. The stack
// calls the memo slots in one fixed order, so energy+tech drained the whole
// 2-per-frame budget on every election and protect served its frame-25
// empty answer for MINUTES (measured 2026-08-30 via prot-enter: first real
// protect run at 4.4-16 min depending on the game; the commander's never
// ran at all -- which is why the first mexes stood naked for the tick).
const int   MEMO_STARVED = 450;   // 15s
const uint  MEMO_N = 7;
array<array<int>@> gMemoAt;     // per slot: per-askerDef frame stamp
array<array<Want@>@> gMemoW;    // per slot: the pristine cached answer

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
	return ProposeProtect(unit);
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
		for (uint s = 0; s < MEMO_N; ++s) {
			array<int> a(uint(Catalog::gDefCount + 1), -30000);
			array<Want@> ws(uint(Catalog::gDefCount + 1));
			@gMemoAt[s] = a;
			@gMemoW[s] = ws;
		}
	}
	const int ud = int(unit.circuitDef.id);
	if ((ud < 1) || (ud > Catalog::gDefCount))
		return MemoSlotCall(slot, unit);
	if (ai.frame - gMemoAt[slot][ud] < MEMO_TTL) {
		Perf::Note("memo.hit");
		return WantCopy(gMemoW[slot][ud]);
	}
	if (gMemoFreshFrame != ai.frame) {
		gMemoFreshFrame = ai.frame;
		gMemoFreshN = 0;
		gMemoStarvN = 0;
	}
	if ((gMemoAt[slot][ud] > -30000) && (gMemoFreshN >= 2)) {
		// Past the normal budget: only a STARVED copy may still recompute,
		// and at most two of those a frame -- see MEMO_STARVED above.
		if ((ai.frame - gMemoAt[slot][ud] <= MEMO_STARVED)
			|| (gMemoStarvN >= 2))
		{
			Perf::Note("memo.defer");
			return WantCopy(gMemoW[slot][ud]);
		}
		++gMemoStarvN;
	}
	++gMemoFreshN;
	Perf::Note("memo.miss");
	Want@ fresh = MemoSlotCall(slot, unit);
	gMemoAt[slot][ud] = ai.frame;
	@gMemoW[slot][ud] = fresh;
	return WantCopy(fresh);
}

// THE FRAME'S ELECTION BUDGET. An election is deferrable work -- a builder
// told "not now" re-asks on its next idle update -- but the sim frame it
// lands on is not: several full stacks plus their executions landing in one
// frame IS the 30-146ms hitch he can feel at 5x speed (the task scheduler
// batches updates, so they cluster). Past the slice, further elections wait.
// Safety (CommanderSafety, the AA panic claim) sits above the check in
// Decide and is never deferred. Spend is fed by the caller (maketask.as)
// so every return path counts without instrumenting each one.
int gElecFrame = -1;
double gElecSpentUs = 0.0;
const double ELEC_FRAME_US = 8000.0;   // a work slice, not policy

void ElecSpend(double us)
{
	if (us > 0.0)
		gElecSpentUs += us;
}

// An executed want of kind K evicts every cached answer of that kind, for
// every asker class -- see the memo's header comment.
void MemoEvictKind(int k)
{
	for (uint s = 0; s < gMemoAt.length(); ++s) {
		array<Want@>@ ws = gMemoW[s];
		array<int>@ at = gMemoAt[s];
		for (uint d = 0; d < ws.length(); ++d) {
			if ((ws[d] !is null) && (ws[d].kind == k))
				at[d] = -30000;
		}
	}
}

IUnitTask@ Decide(CCircuitUnit@ unit)
{
	if ((unit is null) || !unit.circuitDef.IsBuilder() || !unit.circuitDef.IsMobile())
		return null;
	// A unit whose task keeps dying young re-enters every frame; 2s per
	// unit caps the global decide rate without touching legit elections
	// (a successful decide holds its task far longer than this).
	if ((int(unit.id) >= 0) && (int(unit.id) < int(gLastDecideAt.length()))) {
		if (ai.frame - gLastDecideAt[int(unit.id)] < 2 * SECOND)
			return null;
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

	// The frame's election budget -- see ELEC_FRAME_US above. Checked after
	// the safety paths, before the stack.
	if (gElecFrame != ai.frame) {
		gElecFrame = ai.frame;
		gElecSpentUs = 0.0;
	}
	if (gElecSpentUs > ELEC_FRAME_US) {
		Perf::Note("dec.deferred");
		return null;
	}

	array<Want@> wants;
	{ double _t = Perf::T0(); wants.insertLast(ProposeMex(unit)); Perf::Add("want.mex", _t); }
	{ double _t = Perf::T0(); wants.insertLast(MemoPropose(0, unit)); Perf::Add("want.energy", _t); }
	{ double _t = Perf::T0(); wants.insertLast(ProposeGeo(unit)); Perf::Add("want.geo", _t); }
	{ double _t = Perf::T0(); wants.insertLast(ProposePlant(unit)); Perf::Add("want.plant", _t); }
	{ double _t = Perf::T0(); wants.insertLast(ProposeConvert(unit)); Perf::Add("want.convert", _t); }
	{ double _t = Perf::T0(); wants.insertLast(ProposeStore(unit)); Perf::Add("want.store", _t); }
	// MEMOISED like the other heavy walks. Unmemoised it recomputed per
	// BUILDER, and the cost is O(builders x mex spots): measured 2026-08-31 it
	// grew from 1 ms per five-minute block at minute 5 to 1,467 at minute 25,
	// with a 27.2 ms worst call -- the second-largest grower in the game, and
	// the one apexearth described as "noticeably worse as the game progresses".
	// The memo shares one answer per ASKING DEF for MEMO_TTL, which is exactly
	// the sharing every other heavy proposer already had.
	{ double _t = Perf::T0(); wants.insertLast(MemoPropose(6, unit)); Perf::Add("want.mexup", _t); }
	{ double _t = Perf::T0(); wants.insertLast(MemoPropose(1, unit)); Perf::Add("want.tech", _t); }
	{ double _t = Perf::T0(); wants.insertLast(MemoPropose(2, unit)); Perf::Add("want.nano", _t); }
	{ double _t = Perf::T0(); wants.insertLast(MemoPropose(4, unit)); Perf::Add("want.reclobs", _t); }
	{ double _t = Perf::T0(); wants.insertLast(ProposeReclaimBlocker(unit)); Perf::Add("want.reclblk", _t); }
	{ double _t = Perf::T0(); wants.insertLast(ProposeReclaimPenned(unit)); Perf::Add("want.reclpen", _t); }
	{ double _t = Perf::T0(); wants.insertLast(ProposeAssist(unit)); Perf::Add("want.assist", _t); }
	{ double _t = Perf::T0(); wants.insertLast(MemoPropose(5, unit)); Perf::Add("want.protect", _t); }
	{ double _t = Perf::T0(); wants.insertLast(ProposeTeeth(unit)); Perf::Add("want.teeth", _t); }
	{ double _t = Perf::T0(); wants.insertLast(MemoPropose(3, unit)); Perf::Add("want.sense", _t); }
	{ double _t = Perf::T0(); wants.insertLast(ProposeAirDef(unit)); Perf::Add("want.airdef", _t); }
	{ double _t = Perf::T0(); wants.insertLast(ProposeSuper(unit)); Perf::Add("want.super", _t); }
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
	// Highest value first; a want the executor refuses (ground taken, request
	// standing, join out of reach) falls out and the runner-up is tried --
	// a builder never idles while a positive want remains executable.
	array<Want@> ranked;
	for (uint i = 0; i < wants.length(); ++i) {
		Want@ c = wants[i];
		if ((c is null) || (c.value <= 0.f))
			continue;
		uint at = 0;
		while ((at < ranked.length()) && (ranked[at].value >= c.value))
			++at;
		ranked.insertAt(at, c);
	}
	// THEIR AIR WITH NOTHING THAT SHOOTS UP IS AN EMERGENCY, NOT A BID.
	// apexearth: "when enemy starts bombing us and we have 0 AA I expect the
	// very next thing we build to be AA" -- and, later, not to wait for the
	// bombing: seeing their air is the trigger. While it holds, the airdef
	// want skips the lottery rather than taking a proportional share of it.
	// It stops the instant the first tower stands.
	bool aaPanic = false;
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
	if (!aaPanic && !ProtAnyComing(PROT_DEF)
		&& (LossRateAt(Builder::gHomePos) > 0.f))
	{
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
	if (!aaPanic && defClaimOk && !ProtAnyComing(PROT_DEF)
		&& (LossRateAt(Builder::gHomePos) > 0.f))
	{
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if (ranked[ri].kind != WK_PROTECT)
				continue;
			if (ri > 0) {
				Want@ dw = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, dw);
			}
			aaPanic = true;   // reuse the skip-the-lottery flag
			if (ai.frame >= gNextDefPanicLog) {
				gNextDefPanicLog = ai.frame + 15 * SECOND;
				AiLog("apex: DEF PANIC -- losing "
					+ formatFloat(LossRateAt(Builder::gHomePos), "", 0, 2)
					+ " m/s at home with zero defence standing; "
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
	if (!aaPanic && HardEStall()) {
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if ((ranked[ri].kind != WK_ENERGY) && (ranked[ri].kind != WK_GEO))
				continue;
			if (ri > 0) {
				Want@ ew = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, ew);
			}
			aaPanic = true;   // reuse the skip-the-lottery flag
			break;
		}
	}
	// AFFORDABILITY IS THE WHOLE TEST FOR A STRATEGIC BUILD. apexearth: "it is
	// more of a 'if I can afford this, I'll insert it as a want so we make
	// one'." A gantry or a silo returns destruction rather than metal/s, so it
	// can never out-price a mex per metal and a proportional ticket would draw
	// it once a game at best -- which is the state he is reporting. Its own
	// proposer already refuses unless the economy makes the whole bill inside
	// apex_super_afford_s, only one strategic frame stands at a time, and the
	// counts rise with income, so what this skips is the lottery, not a budget.
	bool superPush = false;
	if (!aaPanic && (ai.GetTunable("apex_super_push", TUNE_SUPER_PUSH) > 0.f)) {
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if (ranked[ri].kind != WK_SUPER)
				continue;
			if (ri > 0) {
				Want@ sw = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, sw);
			}
			superPush = true;
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
	if (!aaPanic && !superPush
		&& (ai.GetTunable("apex_cover_push", TUNE_COVER_PUSH) > 0.f))
	{
		const float floorWave = MexCoverFloorM()
				* ai.GetTunable("apex_def_trade", TUNE_DEF_TRADE);
		const float near = Brain::LightTowerRange();
		const AIFloat3 uAt = unit.GetPos(ai.frame);
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			Want@ cw = ranked[ri];
			if ((cw.kind != WK_PROTECT) || (cw.spotId != PROT_DEF))
				continue;
			if (!SiteIsMex(cw.pos) || (uAt.distance2D(cw.pos) > near))
				continue;
			// The same exposure-scaled floor the site loop asks for -- a
			// rear mex's floor is ~zero and the jump must not out-buy it.
			const float floorHere = floorWave * MexFloorFactor(cw.pos);
			if ((floorHere <= 1.f) || (CoverAt(cw.pos) >= floorHere))
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
			if (cw.def !is null) {
				const float aff = ai.GetTunable("apex_cover_push_s",
						TUNE_COVER_PUSH_S);
				if (Catalog::gCostM[int(cw.def.id)] > EcoPowerM() * aff)
					continue;
			}
			if (ri > 0) {
				ranked.removeAt(ri);
				ranked.insertAt(0, cw);
			}
			// HOISTED, NOT EXEMPTED. This used to set coverPush and skip the
			// draw outright, which turned every finished mex into a tower: 96
			// pushes in one game and all 99 early ground-defence decisions were
			// armllt, while metal took 28 of 265 (apexearth, watching: "we
			// don't care enough about capturing mexes early on... the obvious
			// accelerator would be to just capture more mexes, they only cost
			// 30 metal"). A ~100-metal tower on every 30-metal claim halves the
			// expansion rate. Putting it at rank 0 still makes it ground
			// defence's argmax -- and its zero walk is a real price advantage
			// the draw already reads -- but metal keeps its ticket.
			AiLog("apex: cover-push t=" + ai.teamId + " "
				+ ((ranked[0].def is null) ? "?" : ranked[0].def.GetName())
				+ " by " + unit.circuitDef.GetName() + " #" + unit.id
				+ " walk=" + int(uAt.distance2D(ranked[0].pos))
				+ " cover=" + int(CoverAt(ranked[0].pos))
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
	if ((ranked.length() > 1) && !aaPanic && !superPush && !coverPush) {
		array<int> catBest(CAT_N, -1);   // index into ranked, or -1
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
		array<float> wt(CAT_N, 0.f);
		float sumV2 = 0.f;
		for (int c = 0; c < CAT_N; ++c) {
			if (catBest[c] < 0)
				continue;
			const float v = ranked[catBest[c]].value;
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
			{
				const float H = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
				const float cap = EcoPowerM() * ((H > 1.f) ? H : 900.f);
				if ((cap > 1.f) && (ranked[catBest[c]].def !is null)) {
					float bite = ranked[catBest[c]].def.costM / cap;
					if (bite > 1.f)
						bite = 1.f;
					sh += bite * ai.GetTunable("apex_commit_sharp",
							TUNE_COMMIT_SHARP);
				}
			}
			float t = v;
			if ((lead > 0.f) && (sh > 0.f) && (sh != 1.f))
				t = lead * pow(v / lead, sh);
			wt[c] = t;
			sumV2 += t;
		}
		if (sumV2 > 0.f) {
			uint h2 = uint(ai.frame) * 2654435761 + uint(unit.id) * 40503;
			h2 ^= (h2 >> 13);
			float roll2 = float(h2 % 10000) / 10000.f * sumV2;
			for (int c = 0; c < CAT_N; ++c) {
				if (catBest[c] < 0)
					continue;
				roll2 -= wt[c];
				if (roll2 <= 0.f) {
					const int ri = catBest[c];
					if (ri > 0) {
						Want@ drawn = ranked[ri];
						ranked.removeAt(uint(ri));
						ranked.insertAt(0, drawn);
					}
					break;
				}
			}
		}
	}
	Want@ top = (ranked.length() > 0) ? ranked[0] : null;
	Want@ next = (ranked.length() > 1) ? ranked[1] : null;
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
	AiLog("apex: decide t=" + ai.teamId + " " + unit.circuitDef.GetName() + " #" + unit.id
		+ " -> " + CatName(CategoryOf(top.kind))
		+ "/" + KindName(top.kind) + ":" + ((top.def is null) ? "-" : top.def.GetName())
		+ " v=" + formatFloat(top.value * 1000.f, "", 0, 2)
		+ " (gain=" + formatFloat(top.gain, "", 0, 2)
		+ " m=" + formatFloat(top.mCost, "", 0, 0)
		+ " t=" + formatFloat(top.tCost, "", 0, 0) + ")"
		+ ((next is null) ? " over nothing"
			: (" over " + CatName(CategoryOf(next.kind)) + "/" + KindName(next.kind)
				+ " v=" + formatFloat(next.value * 1000.f, "", 0, 2))));

	// THE COMMANDER NEVER TAKES EXPOSED WORK: his death is the game, so a
	// want's exposure is a cost HE pays at game-loss scale (measured: com
	// died at 15:00 building an LLT at a naked forward mex, medium anchor
	// t000 -- the insurance priced the mex's risk and forgot the asker's).
	const bool isComm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	for (uint i = 0; i < ranked.length(); ++i) {
		// FORWARD of the anchor is what kills commanders; the farm-distance
		// radius also banned the rear-flank PLANT site and the commander --
		// early game's only builder -- never made a factory (watched, and it
		// poisoned a 20-game medium anchor). Behind the anchor is safe by
		// the grid's own construction.
		if (isComm && Base::gAnchorSet && Base::gAxisSet) {
			const AIFloat3 rel = ranked[i].pos - Base::gAnchor;
			const float fwdDist = rel.x * Base::gFwd.x + rel.z * Base::gFwd.z;
			// 400: the base-front turret post sits at anchor+150 and the old
			// 150 cutoff banned the commander from it -- mDefence read 0.0
			// for a whole game (apexearth: "in early game he can provide a
			// good defense"). Beyond 400 is the con-and-escort frontier --
			// EXCEPT defence work on or behind our own wall (apexearth:
			// "Commanders are good early game wall makers here because they
			// can defend themselves", and the human meta walks the commander
			// up the lane to wall at the frontier). The wall is the edge of
			// held ground; it and his own guns are what the flat 400 was
			// standing in for.
			if (fwdDist > 400.f) {
				const bool wallWork = (ranked[i].kind == WK_PROTECT)
						&& WallStands()
						&& (WallRimDist(ranked[i].pos) <= 64.f);
				if (!wallWork)
					continue;
			}
		}
		const double _tExec = Perf::T0();
		IUnitTask@ t = ExecuteWant(unit, ranked[i]);
		Perf::Add("exec.want", _tExec);
		Perf::Add("exec.k" + KindName(ranked[i].kind), _tExec);
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
			AiLog("apex: exec t=" + ai.teamId + " " + unit.circuitDef.GetName()
				+ " #" + unit.id + " " + KindName(ranked[i].kind) + ":"
				+ ((ranked[i].def is null) ? "-" : ranked[i].def.GetName())
				+ " pick=" + i
				+ " at=" + int(ranked[i].pos.x) + "," + int(ranked[i].pos.z));
			return t;
		}
		if (uint(ranked[i].kind) < gExecFail.length())
			++gExecFail[ranked[i].kind];
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
	// ...and a refused election is still an idle constructor, which is the
	// exit that actually fires (measured: 472 all-refused elections in one
	// game against zero of the no-want exit above).
	return IdleFloor(unit, "all wants refused");
}


}  // namespace Market
