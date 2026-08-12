namespace Brain {

//------------------------------------------------------------------------------
// QUOTA MODE: A FACTORY IS TOLD HOW MANY, NOT WHAT NEXT.
//
// apexearth: "'Quota Mode' -- where you simply set a desired target quantity and
// the factory will make sure we build up to that quantity", and on how the
// target is reached: "Calculate how much total army you want, then fill up the
// quota to the ratio of those units that you want. (round up). Remember each
// factory has it's own unique quota."
//
// So each driven line holds a target COUNT per unit type, and every tick we
// order only the shortfall -- quota minus what we hold minus what is already on
// its way. A quota that is met orders nothing, which is what bounds production
// without anything having a cap: the target itself is economic.
//
// REPEAT IS OFF, AND THAT IS THE WHOLE POINT. The first version of this file
// laid a composition down and set CmdRepeat(true). apexearth: "With repeat being
// on the amount you've queued will never go down. So you just have factory #s
// that will perpetually keep going higher." Measured in that run: 129 orders
// issued against 253 combat units registered on one line -- production had come
// loose from the plan. Worse, a floor inside the loop can never leave it: the
// constructor was one order in ten, and the re-lay test needed a third of the
// composition to move, so Builder::ConsWantedFor -- the economy curve that is
// supposed to bound constructors -- could not bind at all.
//
// Orders are issued ONE AT A TIME AND INTERLEAVED, round-robin over the types
// that are short, so the line builds the ratio rather than a run of one type.
// apexearth: "If you add 5 then instead of spreading out our build we'll build 5
// of one type and then 5 of the next, etc... that is not good." The count
// argument of CmdBuildUnit is therefore always 1.
//
// THE TWO SCHEMES STILL CANNOT SHARE A FACTORY. CRecruitTask::Finish() calls
// Cancel(), which CmdRemoves every build order still queued, so one recruit task
// on a driven line wipes the shortfall we just ordered. A driven line is held on
// a Wait task and answered by nothing else. See docs/19-factory-through-brain.md.
//------------------------------------------------------------------------------

// The Wait task's timeout, in frames. When it expires the factory goes idle and
// AiMakeTask is called for it again, which is our re-entry point; the orders on
// the line are untouched by any of that.
const int FQ_WAIT = 30 * SECOND;

// HOW MANY OF OUR ORDERS MAY BE ON A LINE AT ONCE. Not a bound on production --
// the quota is that -- but on how much of the shortfall is committed to the
// factory in advance, so the mix can still answer a change in the enemy's army
// instead of it being queued behind seventy raiders. Two is what BAR's own quota
// widget effectively holds: the unit being built, and the next one.
const float FQ_AHEAD_DEFAULT = 2.f;

// How close a finished unit must be to a driven factory to be counted as having
// come off it. Units appear on the factory's build pad.
const float FQ_CLAIM_RANGE = 400.f;

// AN ORDER WE SENT THAT NEVER APPEARS IS PRESUMED LOST AFTER THIS.
//
// The reconciliation below waits for the queue read to confirm what we sent, so
// an order the engine REFUSED -- asking a line for a def it cannot build is a
// silent no-op -- would otherwise wedge the line for the rest of the game. This
// is the escape hatch, and it is deliberately much longer than the worst
// observed application lag (~45 sim-seconds at the benchmark's speed cap).
const int FQ_LOST = 90 * SECOND;

array<Id> gFQId;                 // factories we drive, by id
array<CCircuitUnit@> gFQFac;     // ...and their handles, parallel to gFQId
array<int> gFQSeen;              // ...and the queue depth we last observed
array<int> gFQAt;                // ...and the frame we last sent one an order

// ORDERS SENT BUT NOT YET VISIBLE, as a flat FIFO of (line, def) pairs.
//
// Flat rather than an array-of-arrays because the def is needed too: `have` for
// the ratio is `count + CountQueued(def)`, and BOTH of those lag, so a def we
// have just asked for still reads as zero and wins the ratio again next tick.
// That is how one bot lab committed fifty constructors in its first 45 seconds.
array<int> gFQPendLine;
array<CCircuitDef@> gFQPendDef;

int gFQOrders = 0;               // build orders issued, all lines
int gFQMilReq = 0;               // military task requests, see NoteMilRequest
int gFQLost = 0;                 // orders presumed lost, see FQ_LOST
int gNextFQLog = 0;

void PendAdd(int line, CCircuitDef@ d)
{
	gFQPendLine.insertLast(line);
	gFQPendDef.insertLast(d);
}

int PendCount(int line, CCircuitDef@ d)
{
	int n = 0;
	for (uint i = 0; i < gFQPendLine.length(); ++i) {
		if ((gFQPendLine[i] == line) && ((d is null) || (gFQPendDef[i] is d)))
			++n;
	}
	return n;
}

// Drop the OLDEST n entries for this line: the queue is FIFO, so the orders that
// have become visible are the ones we sent first.
void PendDrop(int line, int n)
{
	for (uint i = 0; (i < gFQPendLine.length()) && (n > 0); ) {
		if (gFQPendLine[i] == line) {
			gFQPendLine.removeAt(i);
			gFQPendDef.removeAt(i);
			--n;
			continue;
		}
		++i;
	}
}

// Lines shift down when one is forgotten, so every stored index must shift too.
void PendReindex(int gone)
{
	for (int i = int(gFQPendLine.length()) - 1; i >= 0; --i) {
		if (gFQPendLine[i] == gone) {
			gFQPendLine.removeAt(i);
			gFQPendDef.removeAt(i);
		} else if (gFQPendLine[i] > gone) {
			gFQPendLine[i] -= 1;
		}
	}
}

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
	gFQSeen.removeAt(i);
	gFQAt.removeAt(i);
	PendReindex(i);
}

// HOW MANY UNITS THIS LINE IS FOR: the unit limit, less what we already hold.
//
// apexearth: "Take a look at your unit limit and divvy up your quota based on
// something reasonable. Let's say you have 100 buildings, 2000 unit limit,
// you're in T1... then your split is on 1900 available units."
//
// The previous sizing was a share of metal we had ALREADY SPENT, and it was
// wrong in the way that matters: it lagged, so a met quota stopped the line, and
// a stopped line is how apex fielded army 0/2700/150/0 against stock's
// 5455/6435/5595/6865 in a 22-minute 4v4.
//
// THE LIMIT IS PER PLAYER, AND IT IS NOT GetUnitMax.
//
// GetUnitMax is unitHandler.MaxUnits() -- the whole map's cap,
// min(maxUnitsPerTeam * activeTeams, 32000). Sized on that, a bot lab's raider
// target came out at 20,296 and every combat ratio printed 0.00, so the
// composition was decided by the order of a C++ array rather than by the mix.
//
// GetUnitLimit is teamHandler.Team(ours)->GetMaxUnits(), which is BAR's
// "Max Units Per Player" modoption: default 2000, min 500, max 32000, and the
// host can change it. That is the budget this divides up.
//
// The quota is TEAM-WIDE, not per line, because the count it is compared against
// is team-wide: CCircuitDef::count is every unit of that def we own, with no way
// to ask which factory made it (the bound surface has no per-factory census, and
// BAR's own quota widget only manages it by watching UnitCreated in unsynced Lua,
// which an AI cannot do). Dividing the target by the number of lines while
// comparing against an undivided count made the team stop at 1/lines of what was
// intended. Each line still gets its own quota in SHAPE -- QuotaFor normalises
// over the roles that line can actually build, so a bot lab and a vehicle plant
// want different things -- and they fill toward one shared target instead of
// double-counting it.
int SlotsForArmy()
{
	const int limit = ai.GetUnitLimit();
	if (limit <= 0)
		return 0;
	// Buildings are the part of the limit that is not army and never will be.
	const int used = ai.GetTeamUnitCount(true);
	const int free = limit - used;
	return (free > 0) ? free : 0;
}

// WHAT A TIER IS STILL WORTH ONCE THE NEXT ONE IS ON THE FIELD.
//
// apexearth: "Later when you get to T2 you reduce your target T1, removing some
// entirely, and now target to create T2 units... later on when T3 is on the
// field, adjust your T2 army accordingly."
//
// Dropping a tier's share below what we already hold is what makes its line go
// quiet, because a quota already met orders nothing. That is the one place in
// this design where the absolute number does real work.
float TierShare(CCircuitDef@ d)
{
	const bool isT2 = (Factory::userData[d.id].attr & Factory::Attr::T2) != 0;
	const bool isT3 = (Factory::userData[d.id].attr & Factory::Attr::T3) != 0;
	if (isT3)
		return 1.f;
	if (isT2)
		return Factory::gHaveT3
			? ai.GetTunable("apex_quota_t2_after_t3", 0.4f) : 1.f;
	if (Factory::gHaveT3)
		return ai.GetTunable("apex_quota_t1_after_t3", 0.f);
	return Factory::gHaveT2
		? ai.GetTunable("apex_quota_t1_after_t2", 0.25f) : 1.f;
}

// How many core T2 fighters count as "protected". Scales with the economy that
// has to be defended rather than being a fixed number.
int T2CoreWanted()
{
	const float inc = Factory::SteadyIncome();
	const float per = ai.GetTunable("apex_t2_core_per_income", 6.f);
	int n = int(inc / per);
	const int floorN = int(ai.GetTunable("apex_t2_core_min", 4.f));
	return (n < floorN) ? floorN : n;
}

// A T2 plant that can already make advanced constructors, and an army that
// cannot yet hold anything.
bool T2ArmyShort(CCircuitUnit@ fac)
{
	if ((Factory::userData[fac.circuitDef.id].attr & Factory::Attr::T2) == 0)
		return false;
	CCircuitDef@ acon = aiFactoryMgr.GetRoleDef(fac.circuitDef, RT::BUILDER2);
	if ((acon is null) || (acon.count <= 0))
		return false;
	array<Type> core = {RT::ASSAULT, RT::HEAVY, RT::AH, RT::AHA};
	int have = 0;
	for (uint i = 0; i < core.length(); ++i) {
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, core[i]);
		if (d !is null)
			have += d.count;
	}
	return have < T2CoreWanted();
}

// Cortex's "scout" IS the resurrection bot -- behaviour.json gives cornecro the
// scout role because the bot lab has no other -- so asking for a scout early
// buys a 130-metal rezzer. apexearth: "we don't need those super early on unless
// there is energy or metal to reclaim that would be useful." Same reclaim test
// the rez floor uses.
bool ScoutWorthIt(CCircuitDef@ scout)
{
	if (scout is null)
		return false;
	if (scout !is Factory::RezBotDef())
		return true;
	return Builder::WreckSeenValue() >= Factory::REZ_METAL_PER_BOT;
}

int RoundUp(float v)
{
	if (v <= 0.f)
		return 0;
	int q = int(v);
	if (float(q) < v)
		++q;
	return q;
}

// THE QUOTA FOR ONE LINE: a target count per unit type it can build.
//
// The combat roles come from the mix -- the same base/counter blend NextForMix
// reads -- turned from a share of metal into a count of units by the cost of the
// unit that fills the role, rounded up. Build power and eyes are quantities
// already, and keep the curves that own them: Builder::ConsWantedFor is what an
// economy is worth in constructors, and the scout floor scales with the ground
// there is to watch.
//
// `isFloor` marks the two entries that are QUANTITIES rather than shares.
// Everything here used to be one flat list ranked by have/want, and that quietly
// handed the composition to array order: a constructor wanting 3 and a raider
// wanting 1200 both read ratio 0.00 while we held none of either, FillQuota broke
// the tie with a strict `<`, and the constructor was simply first in the list. So
// a driven line built constructors and nothing else. Floors are now CHECKED as
// floors -- below the number, build it -- and the ratio only ever chooses between
// combat roles, which is the one thing it is meaningful for.
void QuotaFor(CCircuitUnit@ fac, array<CCircuitDef@>@ defs, array<int>@ want,
		array<bool>@ isFloor)
{
	defs.resize(0);
	want.resize(0);
	isFloor.resize(0);
	InitMix();
	if ((fac is null) || (gMix.length() == 0))
		return;

	// T2 CONS BUT NO T2 ARMY: army is the only thing this line makes.
	//
	// apexearth: "if we have t2 cons but no t2 military then military is our #1
	// priority. we shouldn't build anything like a decoy, a spybot, a raider, bad
	// fighting unit, artillery, if we have too few assault, heavy, or bannisher
	// type T2 military units to protect us."
	if (T2ArmyShort(fac)) {
		array<Type> core = {RT::ASSAULT, RT::HEAVY, RT::AH, RT::AHA};
		for (uint c = 0; c < core.length(); ++c) {
			CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, core[c]);
			if ((d is null) || !d.IsAvailable(ai.frame))
				continue;
			defs.insertLast(d);
			want.insertLast(T2CoreWanted());
			isFloor.insertLast(true);
		}
		if (defs.length() > 0)
			return;      // nothing else off this line until the army exists
	}

	CCircuitDef@ con = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::BUILDER.type);
	if ((con !is null) && con.IsAvailable(ai.frame)) {
		int cap = Builder::ConsWantedFor(con);
		if (aiEconomyMgr.isMetalFull)
			cap = int(float(cap) * ai.GetTunable("apex_con_full_mult", 1.5f)) + 1;
		defs.insertLast(con);
		want.insertLast(cap);
		isFloor.insertLast(true);
	}

	if (ai.GetTunable("apex_mix_scout", 1.f) > 0.f) {
		CCircuitDef@ scout = aiFactoryMgr.GetRoleDef(fac.circuitDef, RT::SCOUT);
		if ((scout !is null) && scout.IsAvailable(ai.frame) && ScoutWorthIt(scout)) {
			const float per = ai.GetTunable("apex_mix_scout_per_mex",
					Targets::At(Targets::SCOUT_PER_MEX));
			int n = 1;
			if (per >= 1.f) {
				CCircuitDef@ mex = SideDef3("armmex", "cormex", "legmex");
				if (mex !is null)
					n = 1 + int(float(mex.count) / per);
			}
			defs.insertLast(scout);
			want.insertLast(n);
			isFloor.insertLast(true);
		}
	}

	// FLOORS THE OLD PRODUCTION RULES USED TO HOLD.
	//
	// A driven line is answered by Brain::FactoryQueueTask and never reaches the
	// rules below it in Factory::AiMakeTask, so RezBotFloor, AirConMinimum and
	// nine others simply stopped running when the Brain took the line. Each of
	// them is a quota in disguise -- "keep N of this thing" -- so each belongs
	// here as a floor entry carrying its own gate, not as a rule that can never
	// fire. Order matters: floors are checked top-down and the first one short
	// wins, so build power stays ahead of eyes, and eyes ahead of these.
	//
	// Rez bots, gated exactly as the rule was: one per REZ_METAL_PER_BOT of wreck
	// we have actually SEEN, capped at REZ_FLOOR. apexearth: "it isn't really
	// important until you have stuff to reclaim or to resurrect."
	if (Factory::HaveT1BotLab()) {
		CCircuitDef@ lab = Factory::T1BotLab();
		CCircuitDef@ rez = Factory::RezBotDef();
		if ((lab !is null) && (rez !is null) && (fac.circuitDef.id == lab.id)
			&& rez.IsAvailable(ai.frame))
		{
			const int byReclaim = int(Builder::WreckSeenValue() / Factory::REZ_METAL_PER_BOT);
			const int n = (byReclaim < Factory::REZ_FLOOR) ? byReclaim : Factory::REZ_FLOOR;
			if (n > 0) {
				defs.insertLast(rez);
				want.insertLast(n);
				isFloor.insertLast(true);
			}
		}
	}

	// One air constructor, so the advanced air plant is reachable at all. The T1
	// air plant's own ratios give constructors ~5%, so a player can hold the air
	// slot all game and never produce one -- and with no advanced plant there are
	// no fighters, because isAvailableDef needs (isActive || IsAttrRare()) and a
	// T1 factory goes inactive the moment its owner has any T2 factory.
	if (Factory::IsAirFactory(fac.circuitDef)) {
		CCircuitDef@ acon = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::BUILDER.type);
		if ((acon !is null) && acon.IsAvailable(ai.frame)) {
			defs.insertLast(acon);
			want.insertLast(Factory::AIR_CON_MIN);
			isFloor.insertLast(true);
		}
	}

	float weight = 0.f;
	array<float> counter = CounterShares(fac, weight);
	array<float> base = BaseShares();

	// The shares are stated over every role in the mix; a line that cannot build
	// half of them would otherwise quietly aim for half an army. Normalising over
	// what this line CAN build is what makes the quota that line's own.
	float sum = 0.f;
	for (uint i = 0; i < gMix.length(); ++i) {
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, gMix[i].role);
		if ((d is null) || !d.IsAvailable(ai.frame))
			continue;
		const float s = Target(i, base, counter, weight);
		if (s > 0.f)
			sum += s;
	}
	if (sum <= 0.f)
		return;

	const float slots = float(SlotsForArmy());
	for (uint i = 0; i < gMix.length(); ++i) {
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, gMix[i].role);
		if ((d is null) || !d.IsAvailable(ai.frame) || (d.costM <= 0.f))
			continue;
		const float s = Target(i, base, counter, weight);
		if (s <= 0.f)
			continue;
		defs.insertLast(d);
		want.insertLast(RoundUp((s / sum) * slots * TierShare(d)));
		isFloor.insertLast(false);
	}
}

// FILLING THE QUOTA, THE WAY BAR'S OWN QUOTA MODE DOES IT.
//
// apexearth: "You are not using Quota mode. You are just adding a lot of things
// on the Queue mode."
//
// He was right, and the reason was mechanical: every earlier version had to
// GUESS what was already on the factory, because nothing in the bound surface
// reads a unit's command queue. Tracking orders by type left phantoms that
// silenced the line; crediting any nearby unit over-credited and kept appending.
// Both are the same mistake in different clothes.
//
// BAR's own widget (luaui/Widgets/unit_factory_quota.lua) does not guess. It
// reads the queue with Spring.GetFactoryCommands, and every 15 frames it adds
// ONE unit -- whichever type has the lowest count/quota ratio -- and only while
// its own previous order is no longer at the head. The queue never grows.
//
// CCircuitUnit::CountQueued reads the same queue but NOT with the same timing,
// and the throttle below is unsound because of it. The widget's order is applied
// before its next read; ours goes out over the network and is applied whenever
// that message is consumed -- measured ~45 sim-seconds later at benchmark speed,
// ~1 at --speed 3. For those 45 ticks this reads an empty line and adds another
// order every tick: 56 orders committed to one bot lab in its first 45 seconds,
// all constructors, which is ~20 minutes of production. A throttle here has to
// count what it SENT and use the queue read only to confirm it.
// See docs/19-factory-through-brain.md, "Bug 1".
//
// Nothing here replaces the factory's queue. A replace would take the unit
// under construction with it, and the widget goes out of its way not to do that
// either -- it refuses to displace a build more than 7.5% done.
// THE ADVANCED CONSTRUCTOR JUMPS THE QUEUE.
//
// apexearth: "(force your advanced cons to build first by giving them an
// inserted queue mode order)".
//
// A new advanced plant is the one moment where order matters more than ratio:
// everything the tier change is for -- upgraded extractors, the T2 economy, the
// plants that follow -- waits on that constructor, and behind a queue of army it
// arrives minutes late. CmdInsertBuild is CMD_INSERT, so it goes to the front
// WITHOUT clearing the queue or touching the unit under construction.
//
// Once per line: gFQConDone records that this line has had its jump.
array<Id> gFQConDone;

bool ConAlreadyJumped(Id id)
{
	for (uint i = 0; i < gFQConDone.length(); ++i) {
		if (gFQConDone[i] == id)
			return true;
	}
	return false;
}

// THE OPENING IS NOT THROWN AWAY WHEN WE TAKE THE LINE.
//
// Taking a factory aborts the recruit tasks on it, which includes the OPENER --
// the specific first units Opener::GetOpener lays down for that plant, in order.
// Green's log, 0.9 min: "facqueue aborted 10 recruit task(s) still holding
// corlab" -- the whole opening, gone, replaced a second later by whatever the
// quota ratio happened to want. apexearth: "green is still not acting normal",
// and it does the same thing every game because the opener is aborted every
// game.
//
// So the opener is re-issued as our own orders. Inserted in REVERSE: CMD_INSERT
// puts each order at the front, so laying them backwards is what makes the queue
// read forwards.
void OpenerFirst(int line)
{
	CCircuitUnit@ fac = gFQFac[line];
	const array<Opener::SO>@ opener = Opener::GetOpener(fac.circuitDef);
	if (opener is null)
		return;
	int laid = 0;
	for (int i = int(opener.length()) - 1; i >= 0; --i) {
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, opener[i].role);
		if ((d is null) || !d.IsAvailable(ai.frame))
			continue;
		// The opener's SCOUT slot is a rez bot on Cortex. See ScoutWorthIt.
		if ((opener[i].role == RT::SCOUT) && !ScoutWorthIt(d))
			continue;
		for (uint j = 0; j < opener[i].count; ++j) {
			fac.CmdInsertBuild(d, true);
			PendAdd(line, d);
			++laid;
		}
	}
	gFQAt[line] = ai.frame;
	gFQOrders += laid;
	AiLog(Factory::T() + "apex: facqueue " + fac.circuitDef.GetName() + " #"
		+ fac.id + " opens with " + laid + " unit(s)");
}

void AdvConFirst(int line)
{
	CCircuitUnit@ fac = gFQFac[line];
	if ((Factory::userData[fac.circuitDef.id].attr & Factory::Attr::T2) == 0)
		return;      // only an advanced plant has an advanced constructor to make
	if (ConAlreadyJumped(fac.id))
		return;
	CCircuitDef@ con = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::BUILDER.type);
	if ((con is null) || !con.IsAvailable(ai.frame))
		return;
	gFQConDone.insertLast(fac.id);
	fac.CmdInsertBuild(con, true);
	PendAdd(line, con);
	gFQAt[line] = ai.frame;
	++gFQOrders;
	AiLog(Factory::T() + "apex: facqueue " + fac.circuitDef.GetName() + " #"
		+ fac.id + " inserts " + con.GetName() + " at the front");
}

void FillQuota(int line)
{
	CCircuitUnit@ fac = gFQFac[line];
	const int ahead = int(ai.GetTunable("apex_fac_ahead", FQ_AHEAD_DEFAULT));
	const int depth = fac.CountQueued(null);

	// RECONCILE WHAT WE SENT WITH WHAT THE ENGINE HAS APPLIED.
	//
	// An AI order is not applied when it is issued: CAICallback::GiveOrder only
	// does clientNet->Send(SendAICommand(...)), and the command lands when that
	// message is consumed -- measured ~45 sim-seconds later at the benchmark's
	// speed cap, ~1 at --speed 3. Topping up against the raw read therefore issues
	// one order per tick for the whole lag window: 56 orders onto one bot lab in
	// its first 45 seconds, all constructors, which is about twenty minutes of
	// production. So the read is treated as DELAYED CONFIRMATION of what we sent,
	// never as the whole truth. Growth in the queue since last tick is our own
	// orders becoming visible.
	const int grew = depth - gFQSeen[line];
	if (grew > 0)
		PendDrop(line, grew);
	gFQSeen[line] = depth;
	// An order the engine refused -- asking a line for a def it cannot build is a
	// silent no-op -- would otherwise wedge this line for the rest of the game.
	if ((PendCount(line, null) > 0) && (ai.frame - gFQAt[line] > FQ_LOST)) {
		gFQLost += PendCount(line, null);
		PendDrop(line, PendCount(line, null));
	}
	if (depth + PendCount(line, null) >= ahead)
		return;

	array<CCircuitDef@> defs;
	array<int> want;
	array<bool> isFloor;
	QuotaFor(fac, defs, want, isFloor);

	// A FLOOR IS CHECKED AS A FLOOR; THE RATIO ONLY CHOOSES BETWEEN COMBAT ROLES.
	// See QuotaFor: one flat ranking by have/want made array order decide the army.
	CCircuitDef@ best = null;
	float worst = 1.0e18f;
	int bestWant = 0;
	for (uint i = 0; i < defs.length(); ++i) {
		if ((want[i] <= 0) || !isFloor[i])
			continue;
		// Held, plus on the line, plus sent-but-not-yet-visible. All three terms
		// are needed: the first two both lag, which is how a floor of three
		// constructors ordered fifty.
		const int have = defs[i].count + fac.CountQueued(defs[i])
				+ PendCount(line, defs[i]);
		if (have < want[i]) {
			@best = defs[i];
			worst = float(have) / float(want[i]);
			break;         // floors are in priority order: build power, then eyes
		}
	}
	if (best is null) {
		for (uint i = 0; i < defs.length(); ++i) {
			if ((want[i] <= 0) || isFloor[i])
				continue;
			const int have = defs[i].count + fac.CountQueued(defs[i])
					+ PendCount(line, defs[i]);
			if (have >= want[i])
				continue;
			const float ratio = float(have) / float(want[i]);
			// Holding none of anything, every ratio is 0 and the tie decided the
			// composition by array order. Break it on the LARGER target: with an
			// empty army, build the thing the mix wants most of. That reproduces
			// the intended ratio from the very first unit instead of from the
			// point where counts diverge.
			if ((ratio < worst - 1.0e-6f)
				|| ((ratio < worst + 1.0e-6f) && (want[i] > bestWant)))
			{
				worst = ratio;
				bestWant = want[i];
				@best = defs[i];
			}
		}
	}
	if (best is null)
		return;      // every quota met: the line stops, which is the point

	// INSERT, NEVER SHIFT-APPEND. FactoryCAI::GetCountMultiplierFromOptions is
	// `if (opts & SHIFT_KEY) ret *= 5`, so every append we made was FIVE units,
	// not one -- which is why the line kept filling up however low the look-ahead
	// was set. apexearth: "you're sending their command with shift, which adds 5",
	// and "queuing army 5 at a time is no good... just queue 2 or 3 of what you
	// want". CMD_INSERT carries no multiplier, which is exactly why BAR's own
	// quota widget uses it rather than a shift-append.
	fac.CmdInsertBuild(best, false);
	PendAdd(line, best);
	gFQAt[line] = ai.frame;
	++gFQOrders;
	if (gFQOrders <= 5 || (gFQOrders % 25 == 0)) {
		string q = "";
		for (uint i = 0; i < defs.length(); ++i)
			q += " " + defs[i].GetName() + "=" + defs[i].count + "/" + want[i];
		AiLog(Factory::T() + "apex: facqueue " + fac.circuitDef.GetName() + " #"
			+ fac.id + " +1 " + best.GetName() + " (have " + best.count
			+ ", quota-ratio " + formatFloat(worst, "", 0, 2)
			+ ", depth " + depth + " pend " + PendCount(line, null)
			+ ") quota:" + q);
	}
}

// A RECRUIT TASK ALREADY ASSIGNED TO THIS FACTORY WILL WIPE OUR QUEUE.
//
// CRecruitTask::Finish() calls Cancel(), which CmdRemoves every build order left
// on the factory -- it does not know, or care, which of them were its own. A line
// we take mid-game has such tasks on it already, from the opener and from
// whatever the mix enqueued before the takeover, and each one that completes
// silences the line until the stuck detector notices 90 seconds later. Measured
// 2026-08-12: a taken vehicle plant produced 5 units in 6 minutes, and the units
// that DID appear were ones we had never ordered.
//
// Factory::gQTask is the pending recruit list, mirrored from the task hooks
// because CFactoryManager::GetTasks is not bound. Aborting is safe here and only
// here: it happens once, before our first order goes down.
void AbortRecruitsOn(CCircuitUnit@ fac)
{
	array<IUnitTask@> doomed;
	for (uint i = 0; i < Factory::gQTask.length(); ++i) {
		IUnitTask@ t = Factory::gQTask[i];
		if (t is null)
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		// An UNSTARTED recruit task -- no factory has taken it -- is the backlog
		// that made CFactoryManager want more factories. Nothing can ever start
		// it once we drive the lines, because a driven line refuses recruits, so
		// it would sit in the pending list for the rest of the game. A factory we
		// do NOT drive can create its own again on its next ask.
		if ((on is null) || (on.length() == 0)) {
			doomed.insertLast(t);
			continue;
		}
		for (uint u = 0; u < on.length(); ++u) {
			if (on[u].id == fac.id) {
				doomed.insertLast(t);
				break;
			}
		}
	}
	// Abort() runs AiTaskRemoved, which mutates gQTask -- collect first, then act.
	for (uint i = 0; i < doomed.length(); ++i)
		doomed[i].Abort();
	if (doomed.length() > 0) {
		AiLog(Factory::T() + "apex: facqueue aborted " + doomed.length()
			+ " recruit task(s) still holding " + fac.circuitDef.GetName()
			+ " #" + fac.id);
	}
}

// Take a line and hold it. The first order replaces whatever is on the factory,
// which clears anything a recruit task left there; repeat is turned off because
// a looping queue is production with no target at all.
IUnitTask@ FactoryQueueTask(CCircuitUnit@ fac)
{
	if (!FacQueueOn() || (fac is null))
		return null;

	int line = FQIndex(fac.id);
	if (line < 0) {
		array<CCircuitDef@> defs;
		array<int> want;
		array<bool> isFloor;
		QuotaFor(fac, defs, want, isFloor);
		if (defs.length() == 0)
			return null;      // not a line we can drive: a nano turret has no roles
		gFQId.insertLast(fac.id);
		gFQFac.insertLast(fac);
		gFQSeen.insertLast(0);
		gFQAt.insertLast(ai.frame);
		line = int(gFQId.length()) - 1;
		AbortRecruitsOn(fac);
		fac.CmdRepeat(false);
		AiLog(Factory::T() + "apex: facqueue takes " + fac.circuitDef.GetName()
			+ " #" + fac.id + " (CRecruitTask off for this line)");
		OpenerFirst(line);
		AdvConFirst(line);
		FillQuota(line);
	}
	return aiFactoryMgr.Enqueue(TaskS::Wait(false, FQ_WAIT));
}

// Recruit orders nobody can ever start, swept up as they appear.
//
// AbortRecruitsOn clears the backlog when a line is TAKEN, which is not enough:
// Factory::AiUnitAdded enqueues an opener for every new factory, and once every
// line is driven those orders can never be assigned to anything. They then sit
// in the pending list forever, and a pending list that never drains is one of
// the things CFactoryManager answers by building another factory -- the seven
// bot labs above. Only while we drive every factory we own; below that, a line
// we do not drive can still take them.
int gNextSweep = 0;

void SweepDeadRecruits()
{
	if (ai.frame < gNextSweep)
		return;
	gNextSweep = ai.frame + 5 * SECOND;
	if ((gFQFac.length() == 0)
		|| (int(gFQFac.length()) < aiFactoryMgr.GetFactoryCount()))
		return;

	array<IUnitTask@> doomed;
	for (uint i = 0; i < Factory::gQTask.length(); ++i) {
		IUnitTask@ t = Factory::gQTask[i];
		if (t is null)
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		if ((on is null) || (on.length() == 0))
			doomed.insertLast(t);
	}
	for (uint i = 0; i < doomed.length(); ++i)
		doomed[i].Abort();
	if (doomed.length() > 0) {
		AiLog(Factory::T() + "apex: facqueue swept " + doomed.length()
			+ " recruit order(s) no line can start");
	}
}

void UpdateFacQueues()
{
	if (!FacQueueOn())
		return;
	for (uint i = 0; i < gFQFac.length(); ++i)
		FillQuota(int(i));
	SweepDeadRecruits();
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
	string d = "";
	for (uint i = 0; i < gFQFac.length(); ++i) {
		d += " #" + gFQFac[i].id + ":" + gFQFac[i].CountQueued(null)
			+ "+" + PendCount(int(i), null);
	}
	AiLog(Factory::T() + "apex: facqueue lines=" + gFQFac.length()
		+ " orders=" + gFQOrders + " lost=" + gFQLost
		+ " slots=" + SlotsForArmy() + " limit=" + ai.GetUnitLimit()
		+ " max=" + ai.GetUnitMax() + " held=" + ai.GetTeamUnitCount(false)
		+ " milreq=" + gFQMilReq + " depth+pend:" + d);
}

}  // namespace Brain
