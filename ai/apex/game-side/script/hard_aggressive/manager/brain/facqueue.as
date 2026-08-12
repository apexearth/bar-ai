namespace Brain {

//------------------------------------------------------------------------------
// OUR OWN STANDING QUEUE, INSTEAD OF ONE CRecruitTask PER UNIT.
//
// apexearth: "Can we try *not* using the original CircuitAI method to make units
// and instead use our method?" and "I want to watch a game with it all working
// through brain, and not the old pathway."
//
// A factory driven from here is given a queue the way a player gives one: a list
// of build orders laid down in one go, with repeat on, and then left alone. The
// composition it expresses is the same mix NextForMix walks toward one unit at a
// time -- what changes is that the line never waits to be handed its next order.
//
// THE TWO SCHEMES CANNOT SHARE A FACTORY. CRecruitTask::Finish() calls Cancel(),
// which CmdRemoves every build order still queued on the factory, so under the
// task scheme the first unit to finish wipes the rest of a standing queue. That
// is a mechanism, not a tuning problem: a factory is either ours or CircuitAI's.
// DrivenFactory() is what Factory::AiMakeTask checks to keep the old pathway off
// a line we have taken, and a driven line is held on a Wait task so the factory
// manager considers it busy and never assigns it a recruit.
//
// See docs/19-factory-through-brain.md.
//------------------------------------------------------------------------------

// How many orders one lay-down puts on the line. This is RATIO GRANULARITY, not
// a production cap -- repeat is on, so the line loops the queue for as long as
// it stands. A queue of n can express a share no finer than 1/n.
const float FQ_DEPTH_DEFAULT = 8.f;

// The Wait task's timeout, in frames. When it expires the factory goes idle and
// AiMakeTask is called for it again, which is our re-entry point; the queue on
// the line is untouched by any of that.
const int FQ_WAIT = 30 * SECOND;

// Never re-lay more often than this. A re-lay REPLACES the factory's queue, and
// whatever it was part-way through building is inside that queue.
const int FQ_RELAY_MIN = 20 * SECOND;

// How much of the queue must want to be something else before it is worth
// replacing. Measured 2026-08-12, first run of this path: comparing the plans
// as ORDERED LISTS re-laid every line every 20s without exception -- one slot
// moving between roles rewrites the list -- and a line that consumed ~1.5 units
// per 20s never reached the tail of its queue. That is the old one-at-a-time
// behaviour wearing a queue, so the comparison is by composition and needs a
// real shift, not a reordering.
const float FQ_CHURN_DEFAULT = 0.34f;

array<Id> gFQId;                 // factories we drive, by id
array<CCircuitUnit@> gFQFac;     // ...and their handles, parallel to gFQId
array<string> gFQSig;            // the composition each was last laid with
array<int> gFQFrame;             // when that lay-down happened
// The bucket counts of each line's laid queue, gFQStride wide per line: slot 0
// is the constructor floor, slot 1 the scout floor, then one per mix role.
array<int> gFQBucket;
uint gFQStride = 0;
int gFQLays = 0;                 // lay-downs performed
int gFQOrders = 0;               // build orders issued across all of them

bool FacQueueOn()
{
	return ai.GetTunable("apex_fac_queue_brain", 1.f) > 0.f;
}

int FQIndex(Id id)
{
	for (uint i = 0; i < gFQId.length(); ++i) {
		if (gFQId[i] == id)
			return int(i);
	}
	return -1;
}

// Is this line ours? Factory::AiMakeTask asks before anything else runs.
bool DrivenFactory(CCircuitUnit@ fac)
{
	return (fac !is null) && (FQIndex(fac.id) >= 0);
}

// CCircuitUnit is registered NOCOUNT, so a stored handle is not nulled when the
// engine destroys the unit -- `is null` stays false on freed memory. Every entry
// here must be dropped from AiUnitRemoved, which is what ReleaseFactory does.
void FQForget(Id id)
{
	const int i = FQIndex(id);
	if (i < 0)
		return;
	gFQId.removeAt(i);
	gFQFac.removeAt(i);
	gFQSig.removeAt(i);
	gFQFrame.removeAt(i);
	for (uint b = 0; b < gFQStride; ++b)
		gFQBucket.removeAt(uint(i) * gFQStride);
}

// THE COMPOSITION, AS A LIST OF ORDERS.
//
// The same walk NextForMix does -- whichever role is furthest below its target
// share -- except the pick is repeated against a running total that includes
// what this queue has already asked for. That is what turns one decision into a
// queue that states a ratio rather than n copies of the same unit.
array<CCircuitDef@> PlanForQueue(CCircuitUnit@ fac, array<int>@ buckets)
{
	array<CCircuitDef@> plan;
	InitMix();
	gFQStride = gMix.length() + 2;
	buckets.resize(gFQStride);
	for (uint b = 0; b < gFQStride; ++b)
		buckets[b] = 0;
	if ((fac is null) || (gMix.length() == 0))
		return plan;

	// Build power first, for the reason BuildPowerFirst states: combat shares are
	// always the largest gap, so a constructor inside the ratio is never chosen.
	// The curve, and what a full bank does to it, are Builder::ConsWantedFor's.
	CCircuitDef@ con = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::BUILDER.type);
	if ((con !is null) && con.IsAvailable(ai.frame)) {
		int cap = Builder::ConsWantedFor(con);
		if (aiEconomyMgr.isMetalFull)
			cap = int(float(cap) * ai.GetTunable("apex_con_full_mult", 1.5f)) + 1;
		if (con.count < cap) {
			plan.insertLast(con);
			buckets[0] = 1;
		}
	}

	// Eyes are a floor, not a share -- see ScoutFloor for why a share cannot
	// express a 21-metal unit.
	if (ai.GetTunable("apex_mix_scout", 1.f) > 0.f) {
		CCircuitDef@ scout = aiFactoryMgr.GetRoleDef(fac.circuitDef, RT::SCOUT);
		if ((scout !is null) && scout.IsAvailable(ai.frame)) {
			const float per = ai.GetTunable("apex_mix_scout_per_mex",
					Targets::At(Targets::SCOUT_PER_MEX));
			int want = 1;
			if (per >= 1.f) {
				CCircuitDef@ mex = SideDef3("armmex", "cormex", "legmex");
				if (mex !is null)
					want = 1 + int(float(mex.count) / per);
			}
			if (scout.count < want) {
				plan.insertLast(scout);
				buckets[1] = 1;
			}
		}
	}

	float total = 0.f;
	array<float> held(gMix.length(), -1.f);
	for (uint i = 0; i < gMix.length(); ++i) {
		held[i] = HeldOfRole(fac, gMix[i].role);
		if (held[i] > 0.f)
			total += held[i];
	}
	if (total < 1.f)
		total = 1.f;

	float weight = 0.f;
	array<float> counter = CounterShares(fac, weight);
	array<float> base = BaseShares();

	const int depth = int(ai.GetTunable("apex_fac_queue_depth", FQ_DEPTH_DEFAULT));
	for (int n = 0; n < depth; ++n) {
		CCircuitDef@ best = null;
		int bestI = -1;
		float worstGap = -1000.f;
		for (uint i = 0; i < gMix.length(); ++i) {
			if (held[i] < 0.f)
				continue;
			const float gap = Target(i, base, counter, weight) - (held[i] / total);
			if (gap <= worstGap)
				continue;
			CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, gMix[i].role);
			if ((d is null) || !d.IsAvailable(ai.frame))
				continue;
			worstGap = gap;
			bestI = int(i);
			@best = d;
		}
		if (best is null)
			break;
		plan.insertLast(best);
		++buckets[2 + bestI];
		held[bestI] += best.costM;
		total += best.costM;
	}
	return plan;
}

// How much of the composition has moved, as a fraction: 0 when the two queues
// ask for the same things, 1 when they share nothing.
float BucketChurn(array<int>@ have, array<int>@ want)
{
	int diff = 0;
	int sum = 0;
	for (uint b = 0; b < gFQStride; ++b) {
		int d = have[b] - want[b];
		diff += (d < 0) ? -d : d;
		sum += have[b] + want[b];
	}
	if (sum <= 0)
		return 0.f;
	return float(diff) / float(sum);
}

array<int> BucketsOfLine(uint line)
{
	array<int> b(gFQStride, 0);
	for (uint i = 0; i < gFQStride; ++i)
		b[i] = gFQBucket[line * gFQStride + i];
	return b;
}

void StoreBuckets(uint line, array<int>@ buckets)
{
	while (gFQBucket.length() < (line + 1) * gFQStride)
		gFQBucket.insertLast(0);
	for (uint i = 0; i < gFQStride; ++i)
		gFQBucket[line * gFQStride + i] = buckets[i];
}

string PlanSig(array<CCircuitDef@>& in plan)
{
	string s;
	for (uint i = 0; i < plan.length(); ++i)
		s += plan[i].GetName() + ",";
	return s;
}

// Lay the whole queue down in one go. The first order carries no options, which
// REPLACES whatever the factory had; the rest append with SHIFT. Repeat then
// makes the line loop it instead of idling at the end.
void LayQueue(CCircuitUnit@ fac, array<CCircuitDef@>& in plan)
{
	for (uint i = 0; i < plan.length(); ++i)
		fac.CmdBuildUnit(plan[i], 1, i == 0);
	fac.CmdRepeat(true);
	++gFQLays;
	gFQOrders += int(plan.length());
	AiLog(Factory::T() + "apex: facqueue lay #" + gFQLays + " on "
		+ fac.circuitDef.GetName() + " #" + fac.id
		+ " orders=" + plan.length() + " [" + PlanSig(plan) + "]");
}

// Take a line, lay its first queue, and hold it with a Wait so the factory
// manager never hands it a recruit task. Returns null when this unit is not
// something we can drive -- a nano turret has no role defs, so it plans nothing.
IUnitTask@ FactoryQueueTask(CCircuitUnit@ fac)
{
	if (!FacQueueOn() || (fac is null))
		return null;

	int i = FQIndex(fac.id);
	if (i < 0) {
		array<int> buckets;
		array<CCircuitDef@> plan = PlanForQueue(fac, buckets);
		if (plan.length() == 0)
			return null;
		gFQId.insertLast(fac.id);
		gFQFac.insertLast(fac);
		gFQSig.insertLast(PlanSig(plan));
		gFQFrame.insertLast(ai.frame);
		StoreBuckets(gFQId.length() - 1, buckets);
		AiLog(Factory::T() + "apex: facqueue takes " + fac.circuitDef.GetName()
			+ " #" + fac.id + " (CRecruitTask off for this line)");
		LayQueue(fac, plan);
	}
	return aiFactoryMgr.Enqueue(TaskS::Wait(false, FQ_WAIT));
}

// Re-lay a driven line when the composition it should be building has MATERIALLY
// changed -- a different list of orders, not a different tick. Relaying every
// tick is the blind-append bug in a new costume, and it also throws away
// whatever the factory is part-way through building.
void UpdateFacQueues()
{
	if (!FacQueueOn())
		return;
	for (uint i = 0; i < gFQFac.length(); ++i) {
		if (ai.frame - gFQFrame[i] < FQ_RELAY_MIN)
			continue;
		CCircuitUnit@ fac = gFQFac[i];
		array<int> buckets;
		array<CCircuitDef@> plan = PlanForQueue(fac, buckets);
		if (plan.length() == 0)
			continue;
		array<int> have = BucketsOfLine(i);
		if (BucketChurn(have, buckets)
				< ai.GetTunable("apex_fac_queue_churn", FQ_CHURN_DEFAULT))
			continue;
		gFQSig[i] = PlanSig(plan);
		gFQFrame[i] = ai.frame;
		StoreBuckets(i, buckets);
		LayQueue(fac, plan);
	}
}

// WHAT CAME OUT OF THE ORDERS WE ISSUED.
//
// The count is the thing to read first: apexearth reports that in BAR shift adds
// five units at a time and ctrl twenty, and if that multiplier is applied
// engine-side rather than by the UI then every order we append is five units.
// Orders issued against units finished is the measurement that settles it.
int gFQBuilt = 0;
int gFQMilReq = 0;
int gNextFQLog = 0;

void NoteFacQueueUnit()
{
	++gFQBuilt;
}

void NoteMilRequest()
{
	++gFQMilReq;
}

void LogFacQueues()
{
	if (!FacQueueOn() || (gFQFac.length() == 0))
		return;
	if (ai.frame < gNextFQLog)
		return;
	gNextFQLog = ai.frame + 30 * SECOND;
	AiLog(Factory::T() + "apex: facqueue lines=" + gFQFac.length()
		+ " lays=" + gFQLays + " orders=" + gFQOrders
		+ " built=" + gFQBuilt + " milreq=" + gFQMilReq);
}

}  // namespace Brain
