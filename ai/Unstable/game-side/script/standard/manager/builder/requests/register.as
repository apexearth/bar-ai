namespace Requests {

// -- the big-energy class -----------------------------------------------------
//
// EVERY GATE ABOVE KEYS ON DEF ID, AND THE ENERGY LADDER IS SIX DEFS. Measured
// live 2026-08-30 (4v4 Comet, t2 12.6m): "request full armfus" -- the per-def
// duplicate gate refusing correctly -- followed immediately by "request new
// armckfus" and "request new armafus", two more four-thousand-metal reactors,
// because each is a different def with its own cap. apexearth, four times now:
// "there's no reason we should ever make two identical, really expensive
// things right next to each other at the same time."
//
// So expensive energy is governed as ONE CLASS at the chokepoint every
// entrance passes through -- the market's rung, the stall ladder's alternate,
// and C++ build_chain alike.
const float BIG_E_COST = 300.f;   // above solar (155) and wind; advsol 370 up

bool IsBigEnergy(const CCircuitDef@ d)
{
	if (d is null)
		return false;
	const int id = int(d.id);
	if (!Catalog::ValidId(id) || Catalog::gMobile[id])
		return false;
	// A REACTOR IS UNARMED. "Costs a lot and makes energy" also describes a
	// Cerberus (corbhmth: 3100 metal, energymake 450, and a gun), so the
	// serialization meant for reactors was refusing heavy turrets against
	// fusions -- measured live, `bigE-held corbhmth` 53 times in one game,
	// while apexearth watched a mid-map cluster go undefended. A power
	// building has no weapon; that is the whole distinction and it needs no
	// list and no threshold.
	if (Catalog::gSurfT[id] > 0.f || Catalog::gAirT[id] > 0.f)
		return false;
	return (Catalog::gCostM[id] >= BIG_E_COST) && (Catalog::gMakeE[id] > 1.f);
}

// IS ONE ALREADY RISING. Asked of the COMMITMENT LEDGER, not gLive: a frame
// whose request died holds no task, and a gate blind to it founds another
// beside it (measured: peak 7 advanced solars with the gLive-based test in).
//
// NO WEALTH EXEMPTION. Three were tried in one session -- bank-covers-the-bill,
// then saturated-or-rich, then saturated-and-rich -- and every one of them was
// the clause the overlaps came back through, because a cheap-enough class
// member saturates at whatever crew the arithmetic allows and a mid-game bank
// covers the rest. The older "more than 1 of any building at one time if we
// are wealthy enough" ruling stands for buildings at large; it never meant
// reactors, which is the class he has now objected to four times. Converters,
// nanos, defence, and the sub-bar generators keep their parallelism.
bool BigEnergyRising()
{
	uint room = 0;
	return Market::ComBigEnergyRising(room) > 0;
}

// THE SLOT BELONGS TO THE BEST REACTOR WANTED, NOT THE FIRST ASKER.
//
// One-at-a-time refused the LATER request, whoever it was, so a 370-metal
// advanced solar routinely held the door shut against a 4,500-metal fusion:
// measured live 2026-08-30, `bigE-held corfus` 99 times in one game, while
// T1 cons executed coradvsol 391 times against 55 fusions (apexearth: "a lot
// of T1 cons are taking up the request to make energy and they're making the
// dramatically inferior advsol when fusions should get made instead").
//
// So a want may open a second site only if it produces STRICTLY MORE energy
// than anything of its class already rising. That is a comparison, not a
// threshold, and it cannot bring back the original bug -- seven advanced
// solars all make 75 e/s, so no member of an equal-output group can ever
// preempt another, and the ladder's depth bounds the overlap.
bool BigEnergyBetterThanRising(const CCircuitDef@ d)
{
	if (d is null)
		return false;
	const int id = int(d.id);
	if (!Catalog::ValidId(id))
		return false;
	return Catalog::gMakeE[id] > Market::ComBigEnergyBestMakeE();
}

int gBigEFold = 0;   // cross-def folds onto the standing reactor
int gBigEHeld = 0;   // refusals: something big is rising and has room
int gBigEPre  = 0;   // a strictly better rung opened its own site

// -- the register ------------------------------------------------------------

array<IUnitTask@> gLive;
// THE WAIT BETWEEN DECIDING AND BREAKING GROUND, per request, parallel to
// gLive (apexearth: "if you build 1 wind -- what's the time between wanting
// to create one and it actually starting? track those timelines"). Nothing
// prices this yet; the log line is the instrument.
array<int> gLiveAt;          // frame Register saw it
array<bool> gLiveStarted;    // its nanoframe has been logged
// The fleet's running mean of that wait, in seconds -- measured, not chosen,
// so the ladder can charge every building the walk it actually costs.
float gStartLatSum = 0.f;
int gStartLatN = 0;
float StartLatencyS()
{
	return (gStartLatN > 0) ? (gStartLatSum / float(gStartLatN)) : 0.f;
}
// THE LATHE A BUILDING ACTUALLY GOT, per def: build time over the seconds from
// its nanoframe to its finish, averaged over what we have finished. The crew
// the request layer would admit is not the crew that shows up -- an advanced
// fusion the cap allowed seven hands took 817 s, which is two -- and the
// simulator's build times were wrong by that ratio. 0 until one has finished.
array<int> gLiveStartAt;          // frame the nanoframe was first seen
array<float> gEffBPSum(ai.GetDefCount() + 1, 0.f);
array<int> gEffBPN(ai.GetDefCount() + 1, 0);
// ...and for the reactor CLASS as a whole, so the first advanced fusion is
// priced at the lathe the fusions actually got rather than at the crew the cap
// would admit.
float gEffBPBigSum = 0.f;
int gEffBPBigN = 0;
float EffBPFor(int defId)
{
	if ((defId < 0) || (defId >= int(gEffBPN.length())))
		return 0.f;
	if (gEffBPN[defId] > 0)
		return gEffBPSum[defId] / float(gEffBPN[defId]);
	if ((gEffBPBigN > 0) && IsBigEnergy(Catalog::Def(defId)))
		return gEffBPBigSum / float(gEffBPBigN);
	return 0.f;
}

void LatencySweep()
{
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((i >= gLiveStarted.length()) || gLiveStarted[i] || (t is null)
			|| t.IsDead() || (t.target is null) || (t.buildDef is null))
			continue;
		gLiveStarted[i] = true;
		if (i < gLiveStartAt.length())
			gLiveStartAt[i] = ai.frame;
		gStartLatSum += float(ai.frame - gLiveAt[i]) / float(SECOND);
		++gStartLatN;
		AiLog(Factory::T() + "apex: latency " + t.buildDef.GetName()
			+ " start=" + ((ai.frame - gLiveAt[i]) / SECOND)
			+ " workers=" + Workers(t)
			+ " m=" + int(t.buildDef.costM));
	}
}

// HOW MANY HANDS ONE SITE CAN ACTUALLY BE FED. A lathe pulls a roughly constant
// DRAIN whatever it is building, so the hands an economy can keep working at
// once is income/DRAIN -- that is InFlightCap. Split across the sites actually
// standing, it is the crew past which another pair of hands adds no progress
// here and only absence somewhere else. Cost decides how LONG a site drains,
// never how many may drain it at once; keying crew size on cost is what let a
// ~10k afus authorise 22 workers while defences and open spots went unbuilt.
// Scales with income and with how much else is in flight -- no flat number.
uint LiveSiteCount()
{
	uint n = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead() || (t.GetType() != Task::Type::BUILDER))
			continue;
		++n;
	}
	return (n > 0) ? n : 1;
}

// Income buildings keep a bigger crew: they finish fast on purpose and pay for
// everything downstream (apexearth, after the first peeled game: "we a little
// bit do not focus enough on eco now"). The multiplier is the eco-vs-rest
// balance knob, now applied to a rate rather than to a cost.
bool IsEcoDef(const CCircuitDef@ want)
{
	if (want is null)
		return false;
	const int d = int(want.id);
	return (Catalog::gMakeE[d] > 1.f) || (Catalog::gExtractsM[d] > 0.f)
			|| (Catalog::gConvCapacity[d] > 0.f);
}

uint FeedableCrew(const CCircuitDef@ want)
{
	// Same exemption as SiteWorkerCap, and the same number: a banked job's
	// crew is bounded by cost, so the peel rung cannot trim what the join
	// rung admitted (peeling against a different number only cycles them).
	if (BankCovers(want))
		return CostCrew(want);
	float n = float(InFlightCap()) / float(LiveSiteCount());
	if (IsEcoDef(want))
		n *= ai.GetTunable("apex_peel_eco_keep", TUNE_PEEL_ECO_KEEP);
	return (n < 1.f) ? 1 : uint(n);
}

// LATHE IS CREW (apexearth: "avoid having cons assist making nanos which are
// near other nanos which can already assist it. This should help us get more
// individual builders creating more nanos"). A standing nano finishes any
// frame its reach covers -- the patrol auto-assist plus the C++ repair
// fallback -- but only a mobile constructor can FOUND the next frame, so a
// join here spends the one thing the cluster cannot supply and parks the
// builder out of the auction for the whole build. Refused when the lathe
// already on the site clears the remaining bill within the joiner's walk
// plus apex_nano_fed_s; a fusion's long middle still takes hands, only the
// covered tail sheds them. Founders are exempt: a site with no workers has
// nobody to raise or guard the frame, whatever lathe stands nearby.
bool NanoFed(IUnitTask@ cand, uint busy, float dist, float speed)
{
	if ((cand is null) || (busy == 0) || (cand.target is null))
		return false;
	const float fedS = ai.GetTunable("apex_nano_fed_s", TUNE_NANO_FED_S);
	if (fedS <= 0.f)
		return false;
	const AIFloat3 where = cand.GetBuildPos();
	if (!OnMap(where))
		return false;
	float lathe = Market::NanoLatheReaching(where);
	if (lathe <= 0.f)
		return false;
	// One nano works one frame at a time: share the lathe across the frames
	// standing in the same cluster, or five frames would each claim the same
	// two turrets.
	uint frames = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead() || (t.target is null))
			continue;
		const AIFloat3 tp = t.GetBuildPos();
		if (OnMap(tp) && (where.distance2D(tp) < 400.f))
			++frames;
	}
	if (frames > 1)
		lathe /= float(frames);
	const float costM = (cand.buildDef !is null) ? cand.buildDef.costM : 0.f;
	const float remainM = costM * (1.f - Progress(cand));
	const float v = (speed > 1.f) ? speed : ASSUMED_CON_SPEED;
	return remainM / lathe <= dist / v + fedS;
}

int gDupLog = 0;
int gCreated = 0;
int gJoined = 0;
int gCovered = 0;    // refused: this ground is already requested
int gFull = 0;       // refused: the income cannot feed another of this def

// PER-DEF, NOT GLOBAL. A single shared cooldown meant a burst on one def (say
// six armadvsol requested close together) could be silenced by an unrelated
// def's log resetting the same timer moments earlier -- exactly the failure
// mode apexearth asked to diagnose (multiple advanced solars appearing to
// build at once with nothing in the log explaining why). Sized and indexed
// like gNextFactoryRequest in sitesafety.as.
array<int> gNextDefLog(ai.GetDefCount() + 1);

// IUnitTask is refcounted, so a held handle stays valid, and every removal
// funnels through DequeueTask -> AiTaskRemoved.
void Register(IUnitTask@ task)
{
	if (task is null)
		return;
	const int bt = task.GetBuildType();
	if (!Governed(bt))
		return;
	if (task.buildDef is null)
		return;
	gLive.insertLast(task);
	gLiveAt.insertLast(ai.frame);
	gLiveStarted.insertLast(false);
	gLiveStartAt.insertLast(-1);
	if (IsBigEnergy(task.buildDef))
		Market::ComBigEInvalidate();
	// WHERE THE EXPENSIVE THING ACTUALLY LANDED. The exec line prints the
	// Want's pos, which the executor's own siting then overrides, so nothing
	// reported whether a build worth parking lathe on ended up inside the
	// lathe we already own.
	if (Market::NanoSinkWorthy(int(task.buildDef.id))) {
		const AIFloat3 sp = task.GetBuildPos();
		if (OnMap(sp))
			AiLog("apex: sink-site " + task.buildDef.GetName()
				+ " at=" + int(sp.x) + "," + int(sp.z)
				+ " ringbp=" + int(Market::RingBPAt(sp))
				+ " gap=" + int(Market::NanoGap(sp)));
	}
}

// Live FACTORY tasks by the synchronous registry -- unlike the builder
// manager's pool count (assignment empties it) or def counts (need a
// nanoframe), this covers a task through its whole walk-and-build window,
// whoever holds it and whoever created it (AiTaskAdded registers engine-made
// tasks too). The plant-ask sweep keys on this so a factory ask can never
// expire while its task is still alive in the commander's hands.
// MANNED only, on purpose: CEconomyManager also keeps a HELD, INACTIVE
// factory task while it waits for income (BuilderManager.cpp:734-740 keeps
// it out of buildTasks for exactly this reason), and AiTaskAdded registers
// that one too. Counting it read "a factory is in flight" from frame ~500 of
// every game, the ask never expired, and no factory was EVER approved --
// facCount=0 at 10 minutes, 2 of 3 smokes. A worker on the task is what
// separates the commander's real walk-and-build from the engine's parked
// placeholder; the unassigned-active ones are the pool count's job.
uint FactoryManned()
{
	uint n = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		if ((gLive[i] !is null) && !gLive[i].IsDead()
			&& (gLive[i].GetBuildType() == Task::BuildType::FACTORY)
			&& (Workers(gLive[i]) > 0))
			++n;
	}
	return n;
}

void Forget(IUnitTask@ task)
{
	for (uint i = 0; i < gLive.length(); ++i) {
		if (gLive[i] is task) {
			if ((gLive[i].buildDef !is null) && IsBigEnergy(gLive[i].buildDef))
				Market::ComBigEInvalidate();
			if ((i < gLiveAt.length()) && (task.buildDef !is null)) {
				// A request that ends with a nanoframe was built; one that
				// ends without one was walked away from.
				AiLog(Factory::T() + "apex: latency " + task.buildDef.GetName()
					+ (gLiveStarted[i] ? " done=" : " dropped=")
					+ ((ai.frame - gLiveAt[i]) / SECOND));
				gLiveAt.removeAt(i);
				if (gLiveStarted[i] && (i < gLiveStartAt.length()) && (gLiveStartAt[i] > 0)
					&& (task.target !is null)) {
					const float secs = float(ai.frame - gLiveStartAt[i]) / float(SECOND);
					const int did = int(task.buildDef.id);
					if ((secs > 1.f) && (did >= 0) && (did < int(gEffBPN.length()))) {
						gEffBPSum[did] += Catalog::gBuildTime[did] / secs;
						++gEffBPN[did];
						if (IsBigEnergy(task.buildDef)) {
							gEffBPBigSum += Catalog::gBuildTime[did] / secs;
							++gEffBPBigN;
						}
					}
				}
				if (i < gLiveStartAt.length())
					gLiveStartAt.removeAt(i);
				gLiveStarted.removeAt(i);
			}
			gLive.removeAt(i);
			return;
		}
	}
}

uint Workers(IUnitTask@ t)
{
	if (t is null)
		return 0;
	array<CCircuitUnit@>@ busy = t.GetUnits();
	return (busy is null) ? 0 : busy.length();
}

// HOW CLOSE TO DONE. `target` is the nanoframe (IBuilderTask::SetTarget,
// null until it exists) and a unit under construction reports its build
// percentage through health percent -- 0 for nothing yet, 1 for finished.
// apexearth: "if we are in progress on more than one, we reassign ourselves
// to focus on the one that is more close to being complete... focus as much
// build power as we can on just the one building". This is the signal that
// lets JoinFor/ClaimFor do that instead of picking on distance
// alone -- a half-built nanoframe should win over a fresh one within reach.
float Progress(IUnitTask@ t)
{
	if (t is null)
		return 0.f;
	CCircuitUnit@ nano = t.target;
	return (nano is null) ? 0.f : nano.GetHealthPercent();
}

// -- buildings of ours already standing half-finished -------------------------
//
// A NANOFRAME OUTLIVES ITS REQUEST. IBuilderTask::OnUnitDestroyed aborts on
// `(target == nullptr) || units.empty()`, so losing the one builder mid-build
// removes the task while the frame stays up; nothing else remembers it, because
// the census credits a structure at AiUnitFinished. Between the two the market
// reads "none standing, none coming", sites another, and a nano turret in range
// quietly finishes the first -- two anti-nukes for one decision.
//
// Ids, not handles: every entry is re-read through ai.GetTeamUnit, so a frame
// that dies between events cannot leave a dangling pointer behind.
// The orphan register LIVES IN THE COMMITMENT LEDGER now (a frame whose
// request died is a FRAMED row with no task -- Market::ComIsOrphan). These
// keep the Requests:: API surface; PendNote keeps only the frame-orphan log
// line the audit reads.
void PendNote(IUnitTask@ task)
{
	if (task is null)
		return;
	CCircuitUnit@ frame = task.target;
	if ((frame is null) || (frame.circuitDef is null))
		return;
	if (frame.circuitDef.IsMobile())
		return;
	const AIFloat3 at = frame.GetPos(ai.frame);
	AiLog(Factory::T() + "apex: frame-orphan " + frame.circuitDef.GetName()
		+ " at=" + int(at.x) + "," + int(at.z)
		+ " done=" + formatFloat(frame.GetHealthPercent(), "", 0, 2));
}

// How many of this def stand unfinished with no request of their own.
uint PendCount(const CCircuitDef@ want)
{
	if (want is null)
		return 0;
	return Market::ComOrphanCount(int(want.id));
}

// The abandoned frame of this def nearest `spot`, within `reach`.
CCircuitUnit@ PendNear(const CCircuitDef@ want, const AIFloat3& in spot, float reach)
{
	if ((want is null) || !OnMap(spot))
		return null;
	return Market::ComOrphanUnit(int(want.id), spot, reach);
}

// ...and the same frame WHEREVER it stands. PendNear answers "is one already
// here", which is the right question when the market has picked a site; it is
// the wrong one when the market has picked a DIFFERENT site, because the
// abandoned frame is then never near anything and is orphaned for good
// (apexearth: "when we e-stall we think to do something else... instead of
// choosing to finish the original lab afterwards we just start making a new
// one"). Nearest to `from` so a fleet of frames is worked in a sane order.
CCircuitUnit@ PendAnyOfDef(const CCircuitDef@ want, const AIFloat3& in from)
{
	if (want is null)
		return null;
	return Market::ComOrphanUnit(int(want.id), from, -1.f);
}

// The same job, for matching purposes. Same def always; and one reactor rung
// counts as another, because HomeEnergy re-ranks fusion against advanced fusion
// every call and each rung was otherwise blind to the other rung's work. Only a
// request somebody is ALREADY on may match across defs: assisting a live
// nanoframe needs no build option, starting one does, and a commander that can
// build armfus cannot build armafus.
bool SameJob(const CCircuitDef@ has, const CCircuitDef@ want, uint busy)
{
	if ((has is null) || (want is null))
		return false;
	if (has.id == want.id)
		return true;
	if (busy == 0)
		return false;
	if (Builder::IsFusion(has) && Builder::IsFusion(want))
		return true;
	// AN ENERGY JOB IS AN ENERGY JOB once hands are on it (apexearth
	// 2026-08-28: T1 cons "go make an advanced solar instead of going to
	// help the T2 fusion being made. Our join logic seems to only care
	// about assisting our own tier"). A T1 con's energy want is the advsol
	// it can place; the standing fusion is the better home for those hands.
	// One direction only -- the standing job must be at least as big as the
	// want it absorbs, or a T2 con's fusion want would downgrade into
	// assisting someone's solar.
	return (has.costM >= want.costM)
		&& (aiEconomyMgr.GetEnergyMake(has) > 1.f)
		&& (aiEconomyMgr.GetEnergyMake(want) > 1.f);
}

}  // namespace Requests
