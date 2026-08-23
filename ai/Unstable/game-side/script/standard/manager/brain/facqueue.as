namespace Brain {

//------------------------------------------------------------------------------
// QUOTA MODE: A FACTORY IS TOLD HOW MANY, NOT WHAT NEXT.
//
// Each driven line holds a target COUNT per unit type, and every tick we order
// only the shortfall -- quota minus what we hold minus what is already on its
// way. A quota that is met orders nothing, which bounds production without a
// cap: the target itself is economic.
//
// REPEAT IS OFF: with repeat on, a floor inside the fill loop can never leave
// it, so the composition comes loose from the plan and one role can consume the
// whole line.
//
// Orders are issued ONE AT A TIME AND INTERLEAVED, round-robin over the types
// that are short, so the line builds the ratio rather than a run of one type.
// The count argument of CmdBuildUnit is therefore always 1.
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

// AN ORDER WE SENT THAT NEVER APPEARS IS PRESUMED LOST AFTER THIS. An order the
// engine REFUSED -- asking a line for a def it cannot build is a silent no-op --
// would otherwise wedge the line for the rest of the game. Deliberately much
// longer than the worst observed application lag (~45 sim-seconds at the
// benchmark's speed cap).
const int FQ_LOST = 90 * SECOND;

// HOW MANY ESCORTS OF ONE KIND EACH SQUAD IS BOUGHT. Bounds a SQUAD's escort,
// not the army's: what gets built is this times the number of qualifying
// squads on the field (EscortSquadCount's value bar), which rises with the
// army the economy can pay for -- no ceiling on the total.
//
// One radar and one jammer per squad. ESCORT_PER_SQUAD in
// task/fighter/SupportTask.cpp is the attachment MAXIMUM (2 of a kind); buying
// under it is safe, buying over it buys escorts no squad will take.
const int ESCORT_PER_SQUAD = 1;

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
	return ai.GetTunable("apex_fac_queue_brain", TUNE_FAC_QUEUE_BRAIN) > 0.f;
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
// THE LIMIT IS PER PLAYER, AND IT IS NOT GetUnitMax. GetUnitMax is
// unitHandler.MaxUnits(), the whole map's cap -- sizing against it inflates
// the target so every combat ratio reads 0.00 and array order decides the
// composition instead of the mix. GetUnitLimit is teamHandler.Team(ours)->
// GetMaxUnits(), BAR's "Max Units Per Player" modoption, which is the actual
// per-player budget.
//
// The quota is TEAM-WIDE, not per line: CCircuitDef::count has no per-factory
// breakdown, so dividing the target by the number of lines while comparing
// against an undivided count stopped the team at 1/lines of what was
// intended. Each line still gets its own quota in SHAPE -- QuotaFor
// normalises over the roles that line can actually build -- and they fill
// toward one shared target instead of double-counting it.
int gNextMixDiag = 0;
int gNextRoleLog = 0;
int gNextRoleDiag = 0;
int gNextEscortDiag = 0;

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

// WHAT A TIER IS STILL WORTH ONCE THE NEXT ONE IS ON THE FIELD. Dropping a
// tier's share below what we already hold makes its line go quiet, since a
// met quota orders nothing.
//
// THE TIER OF THE LINE, NOT OF THE UNIT: Factory::userData carries T2/T3 for
// FACTORY defs only, so asking it about a unit def would answer "T1" for
// everything and zero the target for whatever a gantry could build.
float TierShare(CCircuitUnit@ fac)
{
	const int attr = Factory::userData[fac.circuitDef.id].attr;
	if ((attr & Factory::Attr::T3) != 0)
		return 1.f;
	if ((attr & Factory::Attr::T2) != 0)
		return Factory::gHaveT3
			? ai.GetTunable("apex_quota_t2_after_t3", TUNE_QUOTA_T2_AFTER_T3) : 1.f;
	// 0.15, was 0.0: a hard zero is an off-switch, not a ratio -- the moment
	// a gantry stood, every T1 combat want multiplied to nothing and the lab
	// fell to cons and rezbots (audited iter2: 103 rezbots, 4 Thugs, corthud
	// entries absent from the quota entirely). T1 chaff still screens the
	// slow T3 era, and the enemy fields T1 masses to the end.
	if (Factory::gHaveT3)
		return ai.GetTunable("apex_quota_t1_after_t3", TUNE_QUOTA_T1_AFTER_T3);
	if (!Factory::gHaveT2)
		return 1.f;
	// The cut PHASES IN with the T2 army actually fielded, not the plant
	// standing: apexearth, watching the transition -- "we end up with a small
	// count of T2 versus a lot of enemy T1... we lack enough ranged damage
	// and tankiness as we're transitioning." While the T2 core is thin the T1
	// line keeps near-full weight; at a covered core it bottoms at the tunable.
	const float base = ai.GetTunable("apex_quota_t1_after_t2", TUNE_QUOTA_T1_AFTER_T2);
	float frac = 1.f;
	for (uint i = 0; i < gFQFac.length(); ++i) {
		if ((Factory::userData[gFQFac[i].circuitDef.id].attr & Factory::Attr::T2) == 0)
			continue;
		array<Type> core = {RT::ASSAULT, RT::HEAVY, RT::AH, RT::AHA};
		int have = 0;
		for (uint c = 0; c < core.length(); ++c) {
			CCircuitDef@ d = aiFactoryMgr.GetRoleDef(gFQFac[i].circuitDef, core[c]);
			if (d !is null)
				have += d.count;
		}
		const int wantN = T2CoreWanted();
		frac = (wantN <= 0) ? 1.f : float(have) / float(wantN);
		if (frac > 1.f)
			frac = 1.f;
		break;
	}
	return base + (1.f - base) * (1.f - frac);
}

// How many core T2 fighters count as "protected". Scales with the economy that
// has to be defended rather than being a fixed number.
// Same reactive term `Military::DefenceAllowedAt`'s pressureAllow already
// uses for the defence BUDGET, applied here to the army-vs-constructor FLOOR
// -- confirmed 2026-08-15 there was no such connection anywhere on this side
// at all: facqueue.as had zero references to LosingGround/BaseContested/
// gTurtle before this. apexearth: "if our brain sees we're taking a lot of
// damage it should be prioritizing making army... we don't adapt to the
// situation at all." Scales an EXISTING income-derived floor up under real
// pressure rather than adding a new mechanism or a flat cap; recomputed
// every call, so it relaxes back to normal the moment the pressure clears,
// same as pressureAllow does.
float ArmyPressureMod()
{
	return (Military::LosingGround() || Military::BaseContested())
			? ai.GetTunable("apex_army_pressure_mod", TUNE_ARMY_PRESSURE_MOD) : 1.f;
}

int T2CoreWanted()
{
	const float inc = Factory::SteadyIncome();
	const float per = ai.GetTunable("apex_t2_core_per_income", TUNE_T2_CORE_PER_INCOME);
	int n = int(inc / per * ArmyPressureMod());
	const int floorN = int(ai.GetTunable("apex_t2_core_min", TUNE_T2_CORE_MIN));
	return (n < floorN) ? floorN : n;
}

// A T2 plant that can already make advanced constructors, and an army that
// cannot yet hold anything.
bool T2ArmyShort(CCircuitUnit@ fac)
{
	// Same island gate as T1ArmyShort: a land line builds no walkers it
	// cannot deliver.
	if (Factory::AloneOnIsland() && !Factory::IsAirFactory(fac.circuitDef)
		&& !Factory::IsNavalFactory(fac.circuitDef))
		return false;
	if ((Factory::userData[fac.circuitDef.id].attr & Factory::Attr::T2) == 0)
		return false;
	// Same role gate as T1ArmyShort: the eco role's floors are off too.
	if (EcoRoleArmyOff(fac))
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

// How many T1 front-line units count as "protected". Scales with the economy,
// same shape as T2CoreWanted.
int T1CoreWanted()
{
	const float inc = Factory::SteadyIncome();
	const float per = ai.GetTunable("apex_t1_core_per_income", TUNE_T1_CORE_PER_INCOME);
	int n = int(inc / per * ArmyPressureMod());
	const int floorN = int(ai.GetTunable("apex_t1_core_min", TUNE_T1_CORE_MIN));
	return (n < floorN) ? floorN : n;
}

// Is this line's ARMY output switched off by the eco role? One predicate for
// every army channel -- mix, core floors, spam stream -- because each new
// channel that forgot the role leaked a different unit (six Pawns from the
// T1 core floor, twenty Tumbleweeds from the spam stream on the T2 lab).
bool EcoRoleArmyOff(CCircuitUnit@ fac)
{
	return Role::ArmyMult(fac) <= 0.f;
}

// A LINE THAT HAS NEVER TECHED: no T2/T3 attr, so T2ArmyShort never fires for
// it and the con floor below is the first floor checked -- a line that never
// techs can spend its whole queue on constructors with nothing to stop it.
// RAIDER/RIOT/SKIRM are the roles gMix already builds off a T1 line (see the
// ratio section below), so GetRoleDef is known to resolve them there; ASSAULT/
// HEAVY/AH/AHA are T2ArmyShort's own core and are not what a T1 lab offers.
bool T1ArmyShort(CCircuitUnit@ fac)
{
	// Land army on an island walks nowhere -- apexearth: "not make land army
	// when it is on an island alone." Naval and air lines are unaffected.
	if (Factory::AloneOnIsland() && !Factory::IsAirFactory(fac.circuitDef)
		&& !Factory::IsNavalFactory(fac.circuitDef))
		return false;
	// At a huge economy (or a lagging host) T1 army is clutter -- apexearth:
	// "we should stop making so much T1... the game gets too crazy." The T2+
	// lines carry the army; this line keeps cons and rezbots only.
	if (Builder::CleanupMode() && (Factory::gHaveT2 || Factory::gHaveT3))
		return false;
	const int attr = Factory::userData[fac.circuitDef.id].attr;
	if ((attr & (Factory::Attr::T2 | Factory::Attr::T3)) != 0)
		return false;      // T2ArmyShort covers a line that has already teched
	// The eco role fields no army: this floor is checked before the mix, so
	// without this gate it built exactly T1CoreWanted units on the role
	// holder (six Pawns, measured) while the mix was off.
	if (EcoRoleArmyOff(fac))
		return false;
	array<Type> core = {RT::RAIDER, RT::RIOT, RT::SKIRM};
	int have = 0;
	for (uint i = 0; i < core.length(); ++i) {
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, core[i]);
		if (d !is null)
			have += d.count;
	}
	return have < T1CoreWanted();
}

// Cortex's "scout" IS the resurrection bot -- behaviour.json gives cornecro the
// scout role because the bot lab has no other -- so asking for a scout early
// buys a 130-metal rezzer. Same reclaim test the rez floor uses.
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
// Combat roles come from the mix, turned from a share of metal into a count
// by the cost of the unit that fills the role, rounded up. Build power and
// eyes are quantities already and keep the curves that own them.
//
// Per-def judgement on top of the role shares. Roles map 1:1 to defs on some
// lines (Legion's bot lab: RAIDER=Goblin, SKIRM=Satyr), so a unit that is
// simply weak -- or one that partners another and should flow with it -- has
// no lever but its whole role's share. This is that lever, tunable.
// apexearth 2026-08-15, watching: Satyr is cheap, outranges, and screens
// behind the Karkinos -- more; "Goblin units are really quite bad" -- fewer.
float DefQuotaMod(const CCircuitDef@ d)
{
	if (d is null)
		return 1.f;
	const string n = d.GetName();
	if (n == "leggob")
		return ai.GetTunable("apex_quota_leggob", TUNE_QUOTA_LEGGOB);
	if (n == "leglob")
		return ai.GetTunable("apex_quota_leglob", TUNE_QUOTA_LEGLOB);
	return 1.f;
}

// `isFloor` marks entries that are QUANTITIES rather than shares. A flat list
// ranked by have/want handed the composition to array order when every ratio
// tied at 0.00, so floors are CHECKED as floors -- below the number, build it
// -- and the ratio only ever chooses between combat roles.
void QuotaFor(CCircuitUnit@ fac, array<CCircuitDef@>@ defs, array<int>@ want,
		array<bool>@ isFloor)
{
	defs.resize(0);
	want.resize(0);
	isFloor.resize(0);
	InitMix();
	if ((fac is null) || (gMix.length() == 0))
		return;

	// EYES AND COVER FOR EACH SQUAD -- ABOVE the core-army early returns:
	// armies were fighting blind exactly when fighting, because a perpetually
	// short core floor meant this block was never reached (armmark/armaser
	// quota'd 6+6, ~2 built in a whole watched match). Bounded small, so it
	// cannot eat the line the way the old un-hoisted floors could.
	//
	// NAMED, NOT ASKED FOR BY ROLE. aiFactoryMgr.GetRoleDef(fac, SUPPORT) is a
	// weighted RANDOM DRAW over every main-role-support def the line can build,
	// re-rolled every call -- it is that line's support roulette, not its radar.
	// Factory::EyeDefFor holds the per-faction pair instead.
	//
	// Radar entry first: floors are checked top-down and the first one short
	// wins, so the eyes are bought before the jammer cover.
	//
	// EyeDefFor returns null for every T1 line, because no faction has a T1
	// mobile radar or jammer -- no escorts before T2, by construction.
	{
		// NOT WHILE THEY OUT-MASS US. These are floors, so they are bought
		// BEFORE any combat unit -- a T2 lab answered a push with two mobile
		// jammers (apexearth 2026-08-19). Eyes are worth having for an army
		// that exists; rebuilding one comes first. Releases at parity.
		// NO outmassed gate on either escort. apexearth 2026-08-21, overriding
		// the 2026-08-19 caution outright: "We need 1 jammer and 1 radar on
		// all the expensive squads. Once we get to T2 this is very important.
		// It allows us to shoot at enemies before they can see us. And it
		// prevents them from shooting at us while we're in radar range but
		// they can't see us." The pair is core kit for a fighting army, and
		// being outmassed is when the fighting happens -- the old blanket
		// gate read outmassed in 301/616 diag samples. The floor stays
		// bounded at one of each per qualifying squad.
		const uint squads = Military::EscortSquadCount();
		if (squads > 0) {
			const int per = int(ai.GetTunable("apex_escort_per_squad",
					float(ESCORT_PER_SQUAD)));
			for (int k = 0; k < 2; ++k) {
				CCircuitDef@ eye = Factory::EyeDefFor(fac.circuitDef, k == 1);
				if ((eye is null) || !eye.IsAvailable(ai.frame))
					continue;
				defs.insertLast(eye);
				want.insertLast(per * int(squads));
				isFloor.insertLast(true);
			}
		}
		// Which gate is starving the escorts is unanswerable from the quota
		// line alone -- it only prints defs already IN the quota. apexearth
		// 2026-08-21: "I'm still not seeing those sensor escorts being built."
		if (ai.frame >= gNextEscortDiag) {
			gNextEscortDiag = ai.frame + 60 * SECOND;
			CCircuitDef@ r = Factory::EyeDefFor(fac.circuitDef, false);
			CCircuitDef@ j = Factory::EyeDefFor(fac.circuitDef, true);
			AiLog(Factory::T() + "apex: escort-diag " + fac.circuitDef.GetName()
				+ " squads=" + Military::EscortSquadCount()
				+ " outmassed=" + (Military::Outmassed() ? "1" : "0")
				+ " radar=" + ((r is null) ? "none" : (r.GetName() + ":" + r.count))
				+ " jam=" + ((j is null) ? "none" : (j.GetName() + ":" + j.count)));
		}
	}


	// T2 CONS BUT NO T2 ARMY: army is the only thing this line makes until
	// the core T2 combat roles are covered.
	//
	// NOT floors: floors fill first-listed-first, and the alive-count of the
	// first role never reaches its want while its units die at the front -- so
	// the roles after it never get a single order. As ratio entries the fill
	// loop balances by have/want across the whole core instead.
	if (T2ArmyShort(fac)) {
		array<Type> core = {RT::ASSAULT, RT::HEAVY, RT::AH, RT::AHA};
		for (uint c = 0; c < core.length(); ++c) {
			CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, core[c]);
			if ((d is null) || !d.IsAvailable(ai.frame) || (d.costM <= 0.f))
				continue;
			defs.insertLast(d);
			// Cost-normalized: equal COUNTS of assault and heavy made heavy
			// metal dominate -- see the metal-ratio comment in the fill loop.
			want.insertLast(RoundUp(float(T2CoreWanted())
					* ai.GetTunable("apex_quota_ref_cost", TUNE_QUOTA_REF_COST) / d.costM));
			isFloor.insertLast(false);
		}
		// BUILD POWER IS NOT LOCKED OUT BY THE ARMY. T2CoreWanted scales with
		// income, so at 300 m/s this block is permanently "short" and the
		// early return below starved the con curve entirely: 3 armacks all
		// game against a curve wanting ~18, no hands for the gantry (watched
		// 2026-08-16, zero T3 vs 54k). A balanced ratio entry, so cons
		// interleave with the army instead of pre-empting it.
		// The con want is an ABSOLUTE COUNT from the income curve, not a cost
		// share: normalizing by cost shrank ~18 wanted cons to 3 (armack=7/3
		// in the quota log, conT2 stuck at 4 while stock held 16).
		CCircuitDef@ bcon = aiFactoryMgr.GetRoleDef(fac.circuitDef,
				Unit::Role::BUILDER.type);
		if ((bcon !is null) && bcon.IsAvailable(ai.frame)) {
			defs.insertLast(bcon);
			want.insertLast(Builder::ConsWantedFor(bcon));
			isFloor.insertLast(false);
		}
		if (defs.length() > 0)
			return;      // nothing else off this line until the army exists
	}

	// A T1-ONLY LINE: same idea as T2ArmyShort, for a line that has never
	// teched at all and would otherwise never see anything but the con floor
	// below (see the fill loop's floor-priority-order comment).
	if (T1ArmyShort(fac)) {
		array<Type> core = {RT::RAIDER, RT::RIOT, RT::SKIRM};
		for (uint c = 0; c < core.length(); ++c) {
			CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, core[c]);
			if ((d is null) || !d.IsAvailable(ai.frame))
				continue;
			int n = T1CoreWanted();
			// Post-T2 the WHOLE T1 core drops to a chaff share, not raiders
			// alone. apexearth: Thug/Centurion-class units late are "very
			// expensive and probably not worthwhile. Rezbots, ticks, those
			// are usually what we want... light units to waste enemy fire"
			// -- the trimmed metal flows to T2 army, defence and rezbots
			// through the normal budget instead.
			if (Factory::gHaveT2)
				n = RoundUp(float(n)
						* ai.GetTunable("apex_t1_late_share", TUNE_T1_LATE_SHARE));
			// Cost-normalized like the main fill loop: metal shares, not
			// count shares.
			n = RoundUp(float(n) * DefQuotaMod(d)
					* ai.GetTunable("apex_quota_ref_cost", TUNE_QUOTA_REF_COST)
					/ ((d.costM > 0.f) ? d.costM : 100.f));
			defs.insertLast(d);
			want.insertLast(n);
			isFloor.insertLast(false);      // balanced, not first-listed-first; see T2 block
		}
		if (defs.length() > 0)
			return;      // nothing else off this line until the army exists
	}

	CCircuitDef@ con = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::BUILDER.type);
	if ((con !is null) && con.IsAvailable(ai.frame)) {
		int cap = Builder::ConsWantedFor(con);
		// Not isMetalFull: a bank that is full because the grid is down is a
		// reason to fix the grid, not to buy lathes. See MetalSurplusIsReal.
		if (Builder::MetalSurplusIsReal()) {
			cap = int(float(cap) * ai.GetTunable("apex_con_full_mult", TUNE_CON_FULL_MULT)) + 1;
		} else if ((con.costM < Builder::ADV_CON_COST)
			&& Military::Outmassed())
		{
			// apexearth: a floor of 3 T1 cons; beyond that, more only on surplus
			// metal, and never while the enemy army outweighs ours -- an unfed
			// constructor is army the line did not build.
			const int floorN = int(ai.GetTunable("apex_con_min", TUNE_CON_MIN));
			if (cap > floorN)
				cap = floorN;
		}
		// LAST WORD for the role: cons grow only into the measured BP
		// deficit, surplus included -- a full bank is a deficit the
		// controller already sees, so the multiplier above must not re-raise
		// past it (its doing so was the original undo-the-clamp bug).
		cap = Role::ConCap(con, cap);
		defs.insertLast(con);
		want.insertLast(cap);
		isFloor.insertLast(true);
	}

	// GROUND scouts only -- on an air plant this same role resolves to the
	// air scout and this mex-scaled FLOOR became the 37-scout conveyor the
	// share-capped air-eyes ratio below was written to prevent (his 1v1:
	// 37 armpeep, 6 fighters). Same exclusion the spam stream carries.
	if ((ai.GetTunable("apex_mix_scout", TUNE_MIX_SCOUT) > 0.f)
		&& !Factory::IsAirFactory(fac.circuitDef)) {
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
			// Blind-stance demand lands HERE, on the GROUND scouts a duel
			// actually builds -- the air eyes floor it first multiplied is
			// unreachable in duels (no air lab under the commit; measured
			// airscouts=0 in every A/B game while blind minutes accrued).
			n = int(float(n) * Military::ScoutMult());
			defs.insertLast(scout);
			want.insertLast(n);
			isFloor.insertLast(true);
		}
	}

	// FLOORS THE OLD PRODUCTION RULES USED TO HOLD. A driven line never reaches
	// Factory::AiMakeTask's rules below it, so RezBotFloor, AirConMinimum and the
	// rest simply stopped running when the Brain took the line. Each is a quota
	// in disguise, so each belongs here as a floor entry with its own gate.
	// Order matters: floors are checked top-down, so build power stays ahead of
	// eyes, and eyes ahead of these.
	//
	// Rez bots: the larger of what the wreck field is offering and what the
	// income justifies.
	if (Factory::HaveT1BotLab()) {
		CCircuitDef@ lab = Factory::T1BotLab();
		CCircuitDef@ rez = Factory::RezBotDef();
		if ((lab !is null) && (rez !is null) && (fac.circuitDef.id == lab.id)
			&& rez.IsAvailable(ai.frame))
		{
			const int n = Factory::RezBotsWanted();
			if (n > 0) {
				// SPLIT: a small floor plus the ratio bulk. Pure-ratio starved
				// them to near zero whenever any floor above stayed unmet
				// (ratio draws only run once every floor is satisfied --
				// apexearth, live 8v8: "573 metal income... only 4 rezbots");
				// pure-floor was the earlier conveyor failure (cornecro 4/9
				// unmet, corthud 0/212, "only T1 construction bots were
				// made"). The floor buys the baseline fleet, the ratio buys
				// the rest, and the fraction bounds how much line time dying
				// rezbots can ever convey away.
				const int nFloor = int(float(n)
						* ai.GetTunable("apex_rez_floor_frac", TUNE_REZ_FLOOR_FRAC));
				if (nFloor > 0) {
					defs.insertLast(rez);
					want.insertLast(nFloor);
					isFloor.insertLast(true);
				}
				defs.insertLast(rez);
				want.insertLast(n);
				isFloor.insertLast(false);
			}
		}
	}

	// THE WALL DEMANDS ARTY. Stock's porc-creep won 13 hypothesis arms on
	// Altair because nothing we field outranges an advancing Punisher line:
	// the role draw prices arty at ZERO below tier2 income, and committing
	// T1 guns into the wall is physics that loses (wall-commit arm: 656
	// static metal killed against their 20k walls). Named defs, the
	// eyes-for-the-guns pattern; the floor is SIZED BY THE WALL -- one arty
	// per apex_arty_per_wall of seen enemy static metal, so quiet games buy
	// none and a creeping enemy buys the battery that answers it.
	{
		const float wallSeen = aiEnemyMgr.GetEnemyCost(RT::STATIC);
		const float per = ai.GetTunable("apex_arty_per_wall", TUNE_ARTY_PER_WALL);
		if ((per > 0.f) && (wallSeen > per)) {
			const string fn = fac.circuitDef.GetName();
			string an = "";
			if      (fn == "armvp")  an = "armart";
			else if (fn == "corvp")  an = "corwolv";
			else if (fn == "legvp")  an = "legbar";
			else if (fn == "armavp") an = "armmart";
			else if (fn == "coravp") an = "cormart";
			if (an != "") {
				CCircuitDef@ ad = ai.GetCircuitDef(an);
				if ((ad !is null) && ad.IsAvailable(ai.frame)) {
					defs.insertLast(ad);
					want.insertLast(int(wallSeen / per));
					isFloor.insertLast(false);   // ratio: arty dies too; a floor conveys
				}
			}
		}
	}

	// THE SPAM STREAM. apexearth 2026-08-21: humans keep T1 labs pouring
	// Ticks/Rascals/Rovers all game -- "instead of a sniper getting shot at,
	// it is a unit that costs just ~20 metal, which also provides vision.
	// These are invaluable late game" -- and the raider share fades with
	// income, so the quota stopped buying them exactly when they matter.
	// A RATIO entry, not a floor, for the same conveyor reason as the rez
	// bots above: spam dies constantly, an unmet floor would own the line.
	// Post-T2 only (SpamPhase routes them as no-squad fog scouts); the def
	// must pass IsFodder, which keeps T2 lines' expensive scouts out.
	if (Military::SpamPhase() && !Factory::IsAirFactory(fac.circuitDef)
		&& !EcoRoleArmyOff(fac)) {
		CCircuitDef@ sd = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::SCOUT.type);
		if (!((sd !is null) && Military::IsFodder(sd))) {
			@sd = aiFactoryMgr.GetRoleDef(fac.circuitDef, RT::RAIDER);
			if (!((sd !is null) && Military::IsFodder(sd)))
				@sd = null;
		}
		if ((sd !is null) && sd.IsAvailable(ai.frame)) {
			defs.insertLast(sd);
			want.insertLast(2 + int(aiEconomyMgr.metal.income
					/ ai.GetTunable("apex_spam_per_income", TUNE_SPAM_PER_INCOME)));
			isFloor.insertLast(false);
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
			// Income-derived, not the flat minimum: 6 air cons at 400 m/s
			// left the air arm's build power an afterthought -- apexearth:
			// "I want to see that number be more like 20+. Having more of
			// them should make it more likely that we end up with a T2 air
			// lab at the appropriate time."
			want.insertLast(1 + int(aiEconomyMgr.metal.income
					/ ai.GetTunable("apex_aircon_per", TUNE_AIRCON_PER)));
			isFloor.insertLast(true);
		}
		// TORPEDO BOMBERS ANSWER AN ENEMY IN THE WATER -- ABOVE the fighter and
		// bomber floors, which at late-game income are ~50 aircraft each and
		// would hold this small, urgent floor at the back of the queue exactly
		// when it matters. The AS role only resolves on the advanced plant, and
		// nothing else in the whole quota reacts to an underwater enemy at all.
		// Sized by the sub metal actually seen; an afloat enemy with no subs
		// sighted still earns the first one.
		const float subSeen = Military::EnemyCostOf(Unit::Role::SUB.type);
		if ((subSeen > 0.f) || Military::EnemyAfloat()) {
			CCircuitDef@ torp = aiFactoryMgr.GetRoleDef(fac.circuitDef, RT::AS);
			if ((torp !is null) && torp.IsAvailable(ai.frame)) {
				defs.insertLast(torp);
				want.insertLast(1 + int(subSeen
						/ ai.GetTunable("apex_antisub_per", TUNE_ANTISUB_PER)));
				isFloor.insertLast(true);
			}
		}
		// AT T2 AIR, THE T1 PLANT RETIRES FROM ARMY (apexearth 2026-08-18:
		// "when we're at T2 let's stop making T1 air army... 1200 total
		// fighters, 1000 of which are T1"). Cons and scouts keep coming --
		// the T2 plant's floors take over fighters and bombers with the T2
		// defs GetRoleDef resolves there.
		bool t1AirRetired = false;
		{
			CCircuitDef@ t2ap = SideDef3("armaap", "coraap", "legaap");
			t1AirRetired = (t2ap !is null) && (t2ap.count > 0)
					&& (fac.circuitDef.id != t2ap.id);
		}
		// Resolve bomber and scout defs FIRST so the fighter floor below can
		// size itself off the actual standing fleet -- apexearth 2026-08-21:
		// "at least 1 fighter for every other aircraft we have -- fighters
		// must be >= 50% of the air fleet." Named "other" rather than
		// "bomber" because the old cap (4 + 2*bombers) tracked bombers alone
		// and had no idea scouts existed: bombers stalled low, so the fighter
		// cap stalled at ~4-6 while the scout ratio below kept climbing on
		// its own income term, unopposed by anything fighter-side.
		CCircuitDef@ bomb = aiFactoryMgr.GetRoleDef(fac.circuitDef, RT::BOMBER);
		CCircuitDef@ eye = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::SCOUT.type);
		const int otherAircraft = int(bomb !is null ? bomb.count : 0)
				+ int(eye !is null ? eye.count : 0);
		// FIGHTER COVER, income-scaled like the scouts, floored again by the
		// fleet ratio so fighters cannot be capped below parity by a thin
		// bomber count while scouts keep multiplying beside them.
		CCircuitDef@ wing = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::AA.type);
		if (!t1AirRetired && (wing !is null) && wing.IsAvailable(ai.frame)) {
			int fWant = 1 + int(aiEconomyMgr.metal.income
					/ ai.GetTunable("apex_fighter_per", TUNE_FIGHTER_PER));
			const int fWantRatio = int(float(otherAircraft)
					* ai.GetTunable("apex_fighter_per_other", TUNE_FIGHTER_PER_OTHER));
			if (fWantRatio > fWant)
				fWant = fWantRatio;
			defs.insertLast(wing);
			want.insertLast(fWant);
			isFloor.insertLast(true);
		}
		// BOMBERS ARE THE AIR ARM'S ARMY. The mix path leaves the BOMBER role to
		// whatever slots survive the ground lines, which at 2k income meant a sky
		// of radar planes and no strike force -- apexearth: "we should make lots
		// of bombers and when we have a good mass of bombers we should just find
		// their converters or afus and bomb those." Income-scaled like the
		// fighter floor above it; fighters fill first (floors are top-down), so
		// the escort exists before the strike.
		if (!t1AirRetired && (bomb !is null) && bomb.IsAvailable(ai.frame)) {
			defs.insertLast(bomb);
			want.insertLast(1 + int(aiEconomyMgr.metal.income
					/ ai.GetTunable("apex_bomber_per", TUNE_BOMBER_PER)));
			isFloor.insertLast(true);
		}
		// AIR SCOUTS LAST: floors fill top-down, so eyes only draw once the
		// fighters and bombers ahead of them are met -- apexearth: "Lower the
		// priority on making scout/radar aircraft - they get themselves
		// killed a lot... Fighters, gunships, and bombers should have more
		// priority." Rate halved too (per 120 income, was 60); the map bound
		// still caps the fleet.
		// Same retirement gate as the fighter/bomber floors above: without it
		// a retired T1 air line kept exactly one job -- scout replacement --
		// which is the other half of "air scouts more than any other
		// aircraft, and the lab was often idle" (apexearth): idle while the
		// scouts lived, scout-conveyor when they died, fighters never.
		if (!t1AirRetired && (eye !is null) && eye.IsAvailable(ai.frame)) {
			int eyesN = 1 + int(aiEconomyMgr.metal.income
					/ ai.GetTunable("apex_airscout_per", TUNE_AIRSCOUT_PER));
			// Silence is a scouting demand, not safety: while the stance
			// reads UNKNOWN (nothing fresh seen), the eyes floor doubles --
			// apexearth: "too much silence/unknowns demand proper scouting."
			eyesN = int(float(eyesN) * Military::ScoutMult());
			const int eyesCap = 2 + int(sqrt(float(AiTerrainWidth())
					* float(AiTerrainHeight()))
					/ ai.GetTunable("apex_airscout_map_per", TUNE_AIRSCOUT_MAP_PER));
			if (eyesN > eyesCap)
				eyesN = eyesCap;
			// SCOUTS ARE A SHARE OF THE AIR FLEET, NOT A FLOOR. Scouts die
			// fastest (they fly over the AA to look), so a floor conveyed
			// exactly like the rez floor did: fighters/bombers met their
			// floors and lived, the scout floor never stayed met, and every
			// spare slot became a replacement scout -- apexearth: "air
			// scouts more than any other aircraft... I want to see scouts
			// as 5% or less of our air." Bounded by the STANDING fleet and
			// balanced as a ratio, so they can never out-produce the wings
			// they scout for.
			const int airFleet = int(wing !is null ? wing.count : 0)
					+ int(bomb !is null ? bomb.count : 0);
			int shareCap = 1 + int(float(airFleet)
					* ai.GetTunable("apex_airscout_share", TUNE_AIRSCOUT_SHARE));
			if (eyesN > shareCap)
				eyesN = shareCap;
			defs.insertLast(eye);
			want.insertLast(eyesN);
			isFloor.insertLast(false);
		}
	}

	// A GANTRY THAT IS STANDING IS NEVER IDLE. Named rather than asked for by
	// role: GetFacRoleDef skips any def whose factory.json tier probability is
	// zero, and the super column is 0.00 at tier0, so the role resolves to null
	// exactly when the plant is new. One in flight per plant, since a gantry
	// builds one unit at a time.
	if ((Factory::userData[fac.circuitDef.id].attr & Factory::Attr::T3) != 0) {
		CCircuitDef@ big = Factory::SuperDefFor(fac.circuitDef);
		if ((big !is null) && big.IsAvailable(ai.frame)) {
			defs.insertLast(big);
			want.insertLast(int(fac.circuitDef.count));
			isFloor.insertLast(true);
		}
	}

	float weight = 0.f;
	array<float> counter = CounterShares(fac, weight);
	array<float> base = BaseShares();

	// THE SHARE IS OF THE ARMY, NOT OF THIS LINE. Renormalising over the roles a
	// line could build made every line aim to fill the whole slot budget from
	// whatever roles it had left. Target() already sums to 1 across the mix, so
	// taking it straight makes the budget divide across lines instead of being
	// claimed once per line.
	const float slots = float(SlotsForArmy());
	// THE TECH ROLE PLAYS TECH (apexearth 2026-08-22): the designated
	// tech/eco lead fields no army and turns its own plus the slung metal
	// into economy, the way a human tech player does. Per-tier tunables
	// (0 = no army from that tier's lines, 1 = full mix, fractions scale)
	// so the role can be re-armed from the dashboard. Keyed on IsEcoLead,
	// not IsDesignatedLead: the designation waits on the tech bars, which
	// benchmark income never reaches, while the eco slot is held from frame
	// one (lowest team until a real election) -- a human tech player
	// dedicates from the opening, not from the first Moho. Big teams only
	// by IsEcoLead's own gate, so a 1v1 or small team is untouched, and the
	// mix re-arms the moment the slot moves. Cons/scout/rezzer FLOORS are
	// checked before the mix and stay -- constructors ARE the tech role.
	// The share itself comes from ONE place, Role::ArmyMult -- the mix, the
	// core floors and the spam stream all read the same answer.
	const float leadMult = Role::ArmyMult(fac);
	const bool leadMixRetired = (leadMult <= 0.f);
	if (leadMixRetired && (ai.frame >= gNextRoleLog)) {
		gNextRoleLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: TECH ROLE team=" + ai.teamId
			+ " -- army mix OFF for " + fac.circuitDef.GetName()
			+ " (apex_role_tech_t1/t2/t3)");
	}
	// TEMP DIAG (Tumbleweed hunt): what every role gate reads on this line's
	// pass -- armvader kept appearing in the armalab quota with all known
	// channels gated, so print the gates themselves.
	if (ai.frame >= gNextRoleDiag) {
		gNextRoleDiag = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: role-diag " + fac.circuitDef.GetName()
			+ " ecoLead=" + (Factory::IsEcoLead() ? 1 : 0)
			+ " leadMult=" + formatFloat(leadMult, "", 0, 2)
			+ " armyOff=" + (EcoRoleArmyOff(fac) ? 1 : 0)
			+ " t1Short=" + (T1ArmyShort(fac) ? 1 : 0)
			+ " t2Short=" + (T2ArmyShort(fac) ? 1 : 0)
			+ " spam=" + (Military::SpamPhase() ? 1 : 0));
	}
	const float tier = TierShare(fac) * leadMult;
	// TEMP DIAG: which leg drops each role for this line. Rate-limited; the
	// late-game T1 labs lost every combat entry and three theories in a row
	// were wrong -- this prints the actual reason per role.
	string mixDiag = "";
	// LAG ONLY, NOT WEALTH: this used to fire on CleanupMode's income gate
	// (200 m/s), which on a bonused economy lands right at the T2 switch --
	// the T2 lab is still making cons, the T1 line goes silent, and no one
	// makes army at the most sensitive moment of the game (apexearth: "If we
	// don't have any substantial T2 army yet then let's keep making T1").
	// The handoff itself belongs to TierShare, which phases T1 down as the
	// FIELDED T2 core fills; a hard zero stays only for sim lag, which is a
	// health emergency and not an economy policy.
	const bool t1MixRetired = Perf::GameLagging()
		&& (Factory::gHaveT2 || Factory::gHaveT3)
		&& ((Factory::userData[fac.circuitDef.id].attr
			& (Factory::Attr::T2 | Factory::Attr::T3)) == 0)
		&& !Factory::IsAirFactory(fac.circuitDef);
	// The deepest lag cut: with a gantry running and the host still behind,
	// even T2 army stops -- T3 metal is the same army value in far fewer
	// objects (apexearth: "T2 is mostly unimportant at 500 metal per second").
	const bool t2MixRetired = (Perf::LagSeverity() >= 2.f)
		&& Factory::gHaveT3
		&& ((Factory::userData[fac.circuitDef.id].attr & Factory::Attr::T2) != 0)
		&& !Factory::IsAirFactory(fac.circuitDef);
	for (uint i = 0; i < gMix.length(); ++i) {
		if (t1MixRetired || t2MixRetired || leadMixRetired)
			break;
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, gMix[i].role);
		if (d is null) {
			mixDiag += " r" + int(gMix[i].role) + ":null";
			continue;
		}
		if (!d.IsAvailable(ai.frame) || (d.costM <= 0.f)) {
			mixDiag += " r" + int(gMix[i].role) + ":unavail";
			continue;
		}
		const float s = Target(i, base, counter, weight);
		if (s <= 0.f) {
			mixDiag += " r" + int(gMix[i].role) + ":s0";
			continue;
		}
		mixDiag += " r" + int(gMix[i].role) + ":ok";
		defs.insertLast(d);
		// METAL ratios, not count ratios: the shares are metal shares, and
		// comparing them as raw counts made a 20% heavy share into 20% of
		// SLOTS -- filled with Mammoth-class units at 10-20x a Sheldon's
		// cost, the metal ballooned and the cheap roles starved (apexearth:
		// "we still make tons of metal worth of mammoths versus sheldons...
		// enemy has lots of T1 still but we are refusing to make any").
		// Normalizing the count by cost lands each role's METAL at its share:
		// a 140-metal Sheldon gets ~7x the bodies of a 1000-metal heavy.
		const float ref = ai.GetTunable("apex_quota_ref_cost", TUNE_QUOTA_REF_COST);
		want.insertLast(RoundUp(s * slots * tier * DefQuotaMod(d)
				* (ref / d.costM)));
		isFloor.insertLast(false);
	}
	if (ai.frame >= gNextMixDiag) {
		gNextMixDiag = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: mix-diag " + fac.circuitDef.GetName()
			+ " tier=" + formatFloat(tier, "", 0, 2)
			+ " slots=" + int(slots) + mixDiag);
	}
}

// FILLING THE QUOTA, THE WAY BAR'S OWN QUOTA MODE DOES IT.
//
// BAR's own widget (luaui/Widgets/unit_factory_quota.lua) reads the queue with
// Spring.GetFactoryCommands and adds ONE unit every 15 frames, whichever type
// has the lowest count/quota ratio, only while its own previous order is no
// longer at the head -- the queue never grows.
//
// CCircuitUnit::CountQueued reads the same queue but NOT with the same timing:
// the widget's order is applied before its next read, ours goes out over the
// network and lands whenever that message is consumed -- measured ~45
// sim-seconds later at the benchmark's speed cap. Topping up against the raw
// read for that whole window issues one order per tick, so the throttle here
// counts what it SENT and uses the queue read only to confirm it. See
// docs/19-factory-through-brain.md, "Bug 1".
//
// Nothing here replaces the factory's queue -- a replace would take the unit
// under construction with it.
// THE ADVANCED CONSTRUCTOR JUMPS THE QUEUE. A new advanced plant is the one
// moment where order matters more than ratio: everything the tier change is
// for waits on that constructor, and behind a queue of army it arrives minutes
// late. CmdInsertBuild is CMD_INSERT, so it goes to the front WITHOUT clearing
// the queue or touching the unit under construction.
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

// THE OPENING IS NOT THROWN AWAY WHEN WE TAKE THE LINE. Taking a factory aborts
// the recruit tasks on it, which includes the OPENER -- the specific first
// units Opener::GetOpener lays down for that plant, in order -- so it is
// re-issued as our own orders. Inserted in REVERSE: CMD_INSERT puts each order
// at the front, so laying them backwards is what makes the queue read forwards.
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

// A SURPLUS T1 LINE IS HELD, NOT FED. The plant-count gate stops BUILDING extra
// T1 labs, but resurrection walks straight past it -- rez bots rebuild lab
// wrecks (enemy ones included; cross-faction labs in the Greenhaven ledgers),
// and every fed line drains metal the tech transition needs. Pre-T2, only the
// OLDEST T1 line gets orders; the rest stand until T2 exists. Holding is
// reversible; the labs themselves can still be reclaimed or used later.
bool SurplusT1Line(int line)
{
	if (Factory::gHaveT2)
		return false;
	CCircuitUnit@ fac = gFQFac[line];
	if ((Factory::userData[fac.circuitDef.id].attr & (Factory::Attr::T2 | Factory::Attr::T3)) != 0)
		return false;
	for (uint i = 0; i < uint(line); ++i) {
		if ((Factory::userData[gFQFac[i].circuitDef.id].attr
				& (Factory::Attr::T2 | Factory::Attr::T3)) == 0)
			return true;   // an older T1 line exists; this one waits
	}
	return false;
}

void FillQuota(int line)
{
	CCircuitUnit@ fac = gFQFac[line];
	if (SurplusT1Line(line))
		return;
	const int ahead = int(ai.GetTunable("apex_fac_ahead", TUNE_FAC_AHEAD));
	const int depth = fac.CountQueued(null);

	// RECONCILE WHAT WE SENT WITH WHAT THE ENGINE HAS APPLIED. An AI order is not
	// applied when issued -- CAICallback::GiveOrder just sends it over the
	// network, and it lands whenever that message is consumed -- so the read is
	// treated as DELAYED CONFIRMATION of what we sent, never as the whole truth.
	// Growth in the queue since last tick is our own orders becoming visible.
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
	if (best is null) {
		// EVERY QUOTA MET IS NOT A REASON TO IDLE AT WAR. The wants are
		// BALANCE targets, and the cost-normalization shrank their absolute
		// counts -- measured live: an idle T2 factory for a full minute at a
		// full metal bank while losing (apexearth: "we think we have enough
		// army or something? thats nuts"). With metal to spend, keep building
		// the def whose have/want ratio is lowest; the quota still decides
		// WHAT, it no longer decides WHETHER.
		if (aiEconomyMgr.metal.current
				< aiEconomyMgr.metal.storage
					* ai.GetTunable("apex_overflow_build_frac", TUNE_OVERFLOW_BUILD_FRAC))
			return;
		// COMBAT ONLY: with the army entries missing (the air-table hole)
		// this fallback filled the line with rezbots -- 88 alive in one
		// audited game. Eco defs never overflow-build.
		//
		// FLOOR ENTRIES ARE ELIGIBLE HERE TOO. An air line's fighters, bombers
		// and torps are all floors, and skipping floors made a full-quota air
		// lab idle at a full bank forever -- apexearth: "we have lots of
		// airlabs but we rarely build stuff out of them and we are full on
		// metal." The role screen below is what keeps cons, rezbots and scouts
		// out of the overflow, not the floor flag.
		CCircuitDef@ conD = aiFactoryMgr.GetRoleDef(fac.circuitDef,
				Unit::Role::BUILDER.type);
		CCircuitDef@ rezD = Factory::RezBotDef();
		float worstOver = 1.0e18f;
		for (uint i = 0; i < defs.length(); ++i) {
			if (want[i] <= 0)
				continue;
			if ((defs[i] is conD) || (defs[i] is rezD))
				continue;
			if (defs[i].IsRoleAny(Unit::Role::BUILDER.mask)
				|| defs[i].IsRoleAny(Unit::Role::SCOUT.mask)
				|| defs[i].IsRoleAny(Unit::Role::SUPPORT.mask))
				continue;
			const int have = defs[i].count + fac.CountQueued(defs[i])
					+ PendCount(line, defs[i]);
			const float ratio = float(have) / float(want[i]);
			if (ratio < worstOver) {
				worstOver = ratio;
				@best = defs[i];
			}
		}
		if (best is null)
			return;
	}

	// INSERT, NEVER SHIFT-APPEND. FactoryCAI::GetCountMultiplierFromOptions is
	// `if (opts & SHIFT_KEY) ret *= 5`, so an append is FIVE units, not one.
	// CMD_INSERT carries no multiplier, which is why BAR's own quota widget
	// uses it rather than a shift-append.
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
// on the factory -- it does not know, or care, which of them were its own. A
// line taken mid-game has such tasks on it already, and each one that completes
// silences the line until the stuck detector notices 90 seconds later.
//
// Factory::gQTask is the pending recruit list, mirrored from the task hooks
// because CFactoryManager::GetTasks is not bound. Aborting is safe here and
// only here: it happens once, before our first order goes down.
void AbortRecruitsOn(CCircuitUnit@ fac)
{
	array<IUnitTask@> doomed;
	for (uint i = 0; i < Factory::gQTask.length(); ++i) {
		IUnitTask@ t = Factory::gQTask[i];
		if (t is null)
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		// An UNSTARTED recruit task -- no factory has taken it -- is the backlog
		// that made CFactoryManager want more factories. Once every line is
		// driven, nothing can ever start it (a driven line refuses recruits), so
		// it would sit forever. A factory we do NOT drive can create its own again.
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
// every new factory gets an opener enqueued, and once every line is driven
// those orders can never be assigned to anything and sit in the pending list
// forever -- which is one of the things CFactoryManager answers by building
// another factory. Only while we drive every factory we own; below that, a
// line we do not drive can still take them.
int gNextSweep = 0;

void SweepDeadRecruits()
{
	if (ai.frame < gNextSweep)
		return;
	gNextSweep = ai.frame + 5 * SECOND;
	if (gFQFac.length() == 0)
		return;
	const bool allDriven =
			int(gFQFac.length()) >= aiFactoryMgr.GetFactoryCount();

	array<IUnitTask@> doomed;
	for (uint i = 0; i < Factory::gQTask.length(); ++i) {
		IUnitTask@ t = Factory::gQTask[i];
		if (t is null)
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		if ((on is null) || (on.length() == 0)) {
			// Unstarted backlog: only safe to kill when every line is
			// driven -- an undriven factory can still legitimately take it.
			if (allDriven)
				doomed.insertLast(t);
			continue;
		}
		// ASSIGNED TO A LINE WE DRIVE: the slip channel. The response
		// system's re-enqueue lands on a driven factory inside the
		// GiveOrder lag window and builds units the quota never ordered --
		// Pawns and Tumbleweeds at T1, Bulls at T2 prices (apexearth, three
		// sightings, ~1,600 metal in one game). A driven line's production
		// is the quota's alone, whatever the rest of the fleet looks like.
		bool onDriven = false;
		for (uint u = 0; u < on.length() && !onDriven; ++u) {
			if (on[u] is null)
				continue;
			for (uint g = 0; g < gFQFac.length(); ++g) {
				if ((gFQFac[g] !is null) && (on[u].id == gFQFac[g].id)) {
					onDriven = true;
					break;
				}
			}
		}
		if (onDriven)
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
