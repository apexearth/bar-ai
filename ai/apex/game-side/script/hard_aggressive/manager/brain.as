namespace Brain {

//------------------------------------------------------------------------------
// THE MACRO VIEW. Rules propose; this decides.
//
// apexearth: "what if we created a stack/list of all the things we wanted to do
// and then properly prioritized them after in some process which has a better
// macro view?" and "I want it to generally be a macro-view brain/logic center."
//
// The ladder in builder/maketask.as makes POSITION the only priority: the first
// rule that returns a task wins, so importance is expressed by where a rule sits
// rather than by what it is worth. Measured 2026-08-10: CommanderMexGuard sat
// one line above DefaultMakeTask and took 162 constructor-picks against 4 mex
// upgrades in a single game.
//
// Here a rule states a WANT -- what it would do, what that is worth, what it
// costs -- with no side effects. Decide() ranks the list and only then acts, and
// the whole ranking is logged so a pick can be argued with. docs/18-brain.md
// describes what is built here and what is still only designed.
//
// Only the mex-upgrade want is enqueued by this file. Every other kind names an
// existing rule in Execute(), which keeps its own preconditions -- the ranking
// decides ORDER, not eligibility. A new want therefore needs a Propose() call
// AND a line in Execute(), or it ranks and can never fire.
//
// VALUE IS METAL PER SECOND GAINED, PER METAL SPENT. That is the one unit every
// economic want can be expressed in, and it is why an upgrade can be compared to
// a reactor at all. Defence and offence need their own terms (threat denied,
// enemy metal removed) and are deliberately not here yet.
//------------------------------------------------------------------------------

// How far a constructor will look for one of our extractors to upgrade.
const float MEXUP_REACH = 2400.f;
// What a moho adds over a plain mex, in metal/second, at standard extraction.
// Read from the defs rather than assumed: armmex 1.8/s, armmoho 5.4/s here.
const float MEXUP_INCOME_GAIN = 3.6f;
// A converter turns energy into metal at roughly this rate, which is how an
// energy build is put on the same scale as a metal one.
const float ENERGY_TO_METAL = 0.014f;
// What the one-off investments are worth, in metal/second equivalent. These are
// ESTIMATES and the log prints the score they produce, so they are meant to be
// argued with from a game rather than defended from a desk.
const float GANTRY_VALUE   = 2.0f;   // opens T3 production
const float SILO_VALUE     = 4.0f;   // enemy metal removed, amortised
const float PULSAR_VALUE   = 1.5f;   // area denial near the base
const float PINPOINT_VALUE = 0.5f;   // targeting support, cheap and bounded
// The standing eco rules, as values rather than as "always".
//
// A converter eats 70 energy/s and returns 1 metal/s for ~1 metal to build
// (energyconv_capacity 70, efficiency 1/70, read from armmakr.lua), so while
// energy is spilling it is the best metal-per-metal in the game by a wide
// margin -- and that is exactly the state measured at 41.5% metal waste with
// idle factories. Energy itself is scored on what it unlocks, and is URGENT
// rather than merely valuable when the grid is stalling: UpdateEconomyTasks
// returns early on IsEnergyStalling, so a stall stops every other economy task
// including mex upgrades.
const float CONVERT_VALUE     = 1.0f;    // metal/s per converter, while spilling
// energyconv_capacity, read from the defs: what one converter draws.
const float CONVERT_DRAW      = 70.f;    // armmakr, 1 metal, 1 metal/s back
const float CONVERT_DRAW_BIG  = 600.f;   // armmmkr, 380 metal, 10.3 metal/s back
// One advanced converter replaces about nine cheap ones for a tenth of the
// footprint, so it is worth proportionally more than its raw rate suggests.
const float BIG_CONV_VALUE    = 10.3f;
const float ENERGY_VALUE      = 1.2f;    // metal/s equivalent of a generator step
const float ENERGY_STALL_MULT = 6.0f;    // a stall blocks the whole economy
// BOTH BANKS FULL MEANS INCOME IS NOT THE PROBLEM. apexearth: "if we are full on
// energy AND metal, then we can probably decrease all of our eco priority by
// some multiplier." More income buys nothing when neither resource can be
// stored or spent -- the constraint has moved to build power and to what we do
// with the surplus, so everything economic drops behind the things that spend.
const float ECO_SATED_MULT    = 0.25f;
// BUILD POWER IS WHAT A FULL BANK ACTUALLY NEEDS. apexearth: "in matches where
// we are +100 handicap it's easy to max out the economy and have a hard time
// using all the resources." A nano turret converts banked metal back into units
// at ~7 metal/s of build power for ~300 metal, which beats every income want
// once income is no longer the constraint. Scored high only while sated, so it
// cannot crowd out expansion in a normal game.
const float NANO_VALUE        = 7.0f;
// A front turret repairs instead of producing, so its value is what it keeps
// alive rather than what it builds. Lower than a base nano's build power, and
// it only proposes once there is a front to stand behind.
const float FRONT_NANO_VALUE  = 3.0f;

bool EcoSated()
{
	return aiEconomyMgr.isMetalFull && aiEconomyMgr.isEnergyFull;
}

// ARMY IS NOT THE RESIDUAL. Measured 2026-08-11 across four arms: every cap I
// removed moved metal into constructors, factories and towers, and the standing
// army fell every time -- 4,605 on the pre-Brain build down to 3,943 -- with the
// trade ratio following it down. Nothing in this AI ever gave army a claim on
// metal. Economy wants compete with economy wants, defence has an income budget,
// and the army is whatever is left.
//
// So the economy defers when we are losing the army fight, exactly as it already
// defers when both banks are full. Same shape as ECO_SATED_MULT, opposite cause:
// there the constraint has moved to build power, here it has moved to the front.
// Both are the economy noticing that more income is not the thing we lack.
//
// Scaled by HOW FAR behind, not switched: at parity nothing changes, and the
// damping deepens as the gap does, so this cannot latch us out of expanding.
// EnemyArmyCost only accumulates on sighting, so an unscouted enemy reads small
// and the multiplier stays near 1 -- ignorance never damps the economy.
const float ARMY_DEFICIT_FLOOR = 0.35f;   // most the economy is ever damped

float ArmyDeficitMult()
{
	const float ours = Military::TeamArmyCost();
	const float theirs = Military::EnemyArmyCost();
	if ((theirs <= 1.f) || (ours >= theirs))
		return 1.f;
	const float ratio = ours / theirs;          // 0..1, smaller is worse
	const float floorV = ai.GetTunable("apex_army_deficit_floor", ARMY_DEFICIT_FLOOR);
	return (ratio < floorV) ? floorV : ratio;
}

// Which budget category a want spends from.
Cat BudgetCatOf(const string& in kind)
{
	if ((kind == "nano") || (kind == "frontnano") || (kind == "gantry"))
		return BUILDPOWER;
	// "aa" is anti-air cover and spends from the air-defence row; "fence" is the
	// land line. They shared one kind and one budget until 2026-08-12, which put
	// apexearth's anti-air number in charge of every ground tower. See targets.as.
	if (kind == "aa")
		return AIRDEF;
	if ((kind == "fence") || (kind == "pulsar") || (kind == "silo")
		|| (kind == "pinpoint"))
		return DEFENCE;
	return ECONOMY;
}

// Is this kind's category still short of the share targets.as gives it?
bool UnderBudget(const string& in kind)
{
	const Cat c = BudgetCatOf(kind);
	return ShareOf(c) < TargetShare(c);
}

// The kinds whose whole purpose is more income.
bool IsEcoKind(const string& in kind)
{
	return (kind == "mexup") || (kind == "energy") || (kind == "convert")
		|| (kind == "mex");
}

class Want
{
	string kind;          // "mexup", "gantry", "silo" ... for the log
	float value = 0.f;    // metal/second this is expected to add
	float cost = 1.f;     // metal it takes to get there
	AIFloat3 pos;
	CCircuitDef@ def;
	bool needsAdvCon = false;

	int have = 0;         // how many of this we already hold

	// VALUE PER METAL, WITH DIMINISHING RETURNS.
	//
	// Ranking on value/cost alone hands the game to whatever is cheapest: a
	// Pinpointer at 0.5 metal/s and ~800 metal scores higher than a silo at 4.0
	// and 8,100, so the first ranked run picked pinpoint whenever no upgrade was
	// in reach. Halving the value per copy already standing is what stops one
	// cheap thing winning forever, and it is the real shape -- the second
	// Pinpointer is worth much less than the first.
	float Score() const
	{
		float scaled = value / (1.f + float(have));
		// The category budget: what this purchase is worth against the share of
		// metal its whole category is meant to have. See brain/budget.as -- this
		// is the one place the army/defence/economy/build-power split is stated,
		// and every want now answers to it.
		scaled *= BudgetMult(BudgetCatOf(kind));
		if (IsEcoKind(kind)) {
			if (EcoSated())
				scaled *= ECO_SATED_MULT;
			// Expansion is exempt: taking ground is how we out-produce them back
			// into the fight, and a mex is 50 metal. What defers is the expensive
			// economy -- reactors, converters, upgrades.
			if (kind != "mex")
				scaled *= ArmyDeficitMult();
		}
		return (cost > 1.f) ? (scaled / cost) : scaled;
	}
}

array<Want@> gWants;
int gNextBrainLog = 0;
int gMexUpOrders = 0;
int gMexOrders = 0;
int gFenceOrders = 0;
// Where the orders were AIMED, against where the towers ended up standing. The
// two have been measured only at the end, which cannot tell a request that was
// never forward from a forward tower that never got built.
int gFenceNear = 0;   // ordered inside 0.10 of the way to the enemy
int gFenceMid = 0;    // 0.10 - 0.25
int gFenceFar = 0;    // past 0.25

// DID THE ORDER BECOME A TOWER? Aim and outcome have only ever been measured
// separately -- orders from the log, standing towers from the position gadget --
// and a request aimed at 0.4 that never gets built looks identical, at the end of
// the game, to a request that was never aimed forward at all.
array<AIFloat3> gAimPos;
array<int> gAimAt;
array<IUnitTask@> gAimTask;
int gAimBuilt = 0;
int gAimLost = 0;
int gAimNoWorker = 0;   // still on the books at settle time with nobody on it
int gAimGone = 0;       // task itself was dropped
int gNextAimLog = 0;
const int   AIM_SETTLE = 90 * SECOND;   // long enough to walk there and build
const float AIM_RADIUS = 300.f;

int gAimEarlyOn = 0;    // had a builder on it 10s after the order
int gAimEarlyOff = 0;
array<bool> gAimSeen;

void FenceSweep()
{
	for (int i = int(gAimPos.length()) - 1; i >= 0; --i) {
		// Was it ever picked up at all? Assigned-then-abandoned and never-assigned
		// look identical at settle time, and they have opposite fixes.
		if (!gAimSeen[i] && (ai.frame - gAimAt[i] >= 10 * SECOND)) {
			gAimSeen[i] = true;
			IUnitTask@ e = gAimTask[i];
			array<CCircuitUnit@>@ onE = (e is null) ? null : e.GetUnits();
			if ((onE !is null) && (onE.length() > 0))
				++gAimEarlyOn;
			else
				++gAimEarlyOff;
		}
		if (ai.frame - gAimAt[i] < AIM_SETTLE)
			continue;
		if (Military::FenceCountNear(gAimPos[i], AIM_RADIUS) > 0) {
			++gAimBuilt;
		} else {
			++gAimLost;
			// Which half of the failure it is: an order nobody ever picked up, or
			// one that was picked up and did not survive the attempt.
			IUnitTask@ t = gAimTask[i];
			if (!Builder::IsDefenceTaskLive(t)) {
				++gAimGone;      // aborted or dequeued by the engine
			} else {
				array<CCircuitUnit@>@ on = t.GetUnits();
				if ((on is null) || (on.length() == 0))
					++gAimNoWorker;   // still queued, nobody elected onto it
			}
		}
		gAimPos.removeAt(i);
		gAimAt.removeAt(i);
		gAimTask.removeAt(i);
		gAimSeen.removeAt(i);
	}
	if ((gAimBuilt + gAimLost > 0) && (ai.frame >= gNextAimLog)) {
		gNextAimLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: front-aim built=" + gAimBuilt
			+ " never=" + gAimLost
			+ " picked=" + gAimEarlyOn + "/" + (gAimEarlyOn + gAimEarlyOff)
			+ " (idle=" + gAimNoWorker
			+ " dropped=" + gAimGone + ")"
			+ " pending=" + gAimPos.length());
	}
}
int gNextPickLog = 0;

void Clear()
{
	gWants.resize(0);
}

void Propose(Want@ w)
{
	if (w !is null)
		gWants.insertLast(w);
}

// EXPANSION AS A WANT, NOT AS A POSITION IN A LIST.
//
// apexearth: "potentially, expansion always wins is now being replaced by logic
// in the brain", and "a lot of the concepts and things that I had added in the
// past are now the brain's responsibility."
//
// ExpansionAlwaysWins protects expansion by SITTING EARLY: it takes the engine's
// offer when that offer happens to be a mex. It cannot help when the engine
// offers something else, or nothing -- and the engine's economy generator is
// budgeted (MakeEconomyTasks refuses above workers * 8), so "nothing" is common
// exactly when the base is busiest. Measured 6 games at minute 14: we hold 10
// extractors to stock's 13 and make 12,303 metal to their 17,185.
//
// It does not need protecting once it has a number. A plain extractor yields
// ~1.8 metal/second for ~50 metal, which is 0.033 per metal against a moho
// upgrade's 0.0058 and a reactor's 0.0034 -- expansion outranks an upgrade five
// to one and a reactor ten to one on value alone, which is the right answer and
// the one the ladder was hard-coding by hand.
//
// Any builder, not just an advanced one: taking ground is T1 work.
const float MEX_INCOME_GAIN = 1.8f;   // armmex extraction, read from the defs

Want@ MexWant(CCircuitUnit@ unit)
{
	CCircuitDef@ mex = SideDef3("armmex", "cormex", "legmex");
	if ((mex is null) || !mex.IsAvailable(ai.frame))
		return null;
	// BOUNDED BY BUILD POWER, WHICH IS WHAT ACTUALLY LIMITS EXPANSION. Nothing
	// else does: every open spot is worth the same, so this want re-proposes for
	// every builder on every call and enqueued 97 extractor tasks in one game
	// before this line existed. One outstanding job per worker is the honest
	// ceiling -- a job nobody can walk to is a slot held for 300 seconds against
	// the engine's economy budget.
	if (Builder::OutstandingMexTasks() >= aiBuilderMgr.GetWorkerCount())
		return null;
	const int spot = aiEconomyMgr.FindOpenMexSpot(unit, unit.GetPos(ai.frame));
	if (spot < 0)
		return null;
	Want@ w = Want();
	w.kind = "mex";
	w.value = MEX_INCOME_GAIN;
	w.cost = mex.costM;
	@w.def = mex;
	w.needsAdvCon = false;
	// NOT decayed by how many extractors already stand. Every spot yields the
	// same, and the map runs out of them on its own -- FindOpenMexSpot returning
	// -1 is the only bound this needs.
	w.have = 0;
	return w;
}

// DEFENCE THE BRAIN ASKS FOR, ON THE LINE IT CHOSE.
//
// apexearth: "Make it so we actively place defenses on the frontline. This is
// something the brain should ask for."
//
// Every tower until now was placed by somebody else and merely approved or
// refused here: MexGuard picked the mex, Fortify picked wherever a constructor
// was standing when it got shot, and the gate could only say yes or no to a spot
// it had no part in choosing. Measured across every arrangement of that, 12
// minutes at +50: 0% of our defences sat past a quarter of the way to the enemy
// while stock had a player at 86% forward.
//
// So the Brain proposes a POSITION now. Military::FrontCurve is the influence
// crossing sampled lane by lane across the map, and the pick is the point on it
// that has the least standing near it -- cover spreads along the line before it
// thickens anywhere on it. The def follows the position, as it does at a mex:
// the Beamer where a raid arrives in force, the Sentry behind.
//
// Value is deliberately modest. Defence's real currency is threat denied per
// metal, which this file does not yet speak; what actually bounds it is the
// DEFENCE category budget from targets.as, applied to every want through
// BudgetMult. This one competes there like everything else.
const float FRONT_FENCE_VALUE = 1.2f;
const float FRONT_FENCE_SPREAD = 700.f;   // how far apart cover counts as spread
// HOW FAR TO LOOK FOR GROUND THE TOWER FITS ON.
//
// Was 400 -- less than the 435 range of the cheapest tower it places, and a
// fraction of the 1400 that armanni/cortoast reach. The samples this searches
// around are raw geometry (see the call site), so they land on slopes, in water
// and inside buildings; a lake or a cliff face is routinely wider than 400
// elmos, and FrontLineSpots is deterministic, so a spot that fails once fails on
// every call for the rest of the game. Failure returns null and the want is
// never proposed at all -- silent, and a candidate for why the front line is
// ordered far more often than it is built.
//
// The line's own spacing is computed from the tower's GetMaxRange (about 1120
// elmos apart for an armanni), so a nudge smaller than that cannot even reach
// the neighbouring valid ground. Scaled off the same number for that reason.
const float FRONT_SITE_FRAC = 0.9f;

// A RANGE READ IS NOT AUTOMATICALLY A GUN'S RANGE, AND AN ABSURD ONE MUST NOT BE
// ABLE TO REACH ANYTHING. GetMaxRange is the def's longest weapon, whatever that
// weapon is for: an anti-nuke's interceptor reports 72,000 elmos, and legrampart
// carries one. Read unclamped it set the front line's SPACING and the radius
// FenceCountNear counts cover over, so one such def made the line a single point,
// made every tower on the map count as cover, and drove the want's value to zero
// -- silently, for one faction. This is the second time a bad range read has
// zeroed a want, so the clamp is general: nothing downstream sees a raw range.
//
// Bounded by the longest real static DIRECT-FIRE gun any of the three factions
// fields -- legperdition at 2,300 elmos, 5.35x the light turret's 430-435.
// Anything reporting more than that is carrying artillery or an interceptor, not
// a line gun.
const float DEF_REACH_CAP = 6.0f;

float LightTowerRange()
{
	CCircuitDef@ light = SideDef3("armllt", "corllt", "leglht");
	const float r = (light is null) ? 0.f : light.GetMaxRange();
	return (r > 1.f) ? r : 430.f;   // armllt/leglht 430, corllt 435
}

// The def's usable weapon reach, clamped. Every consumer of a tower's range in
// this file goes through here.
float TowerReach(const CCircuitDef@ tower)
{
	if (tower is null)
		return 0.f;
	const float r = tower.GetMaxRange();
	if (r <= 0.f)
		return 0.f;
	const float cap = LightTowerRange()
			* ai.GetTunable("apex_def_reach_cap", DEF_REACH_CAP);
	return (r > cap) ? cap : r;
}

float FrontSiteSearch(const CCircuitDef@ tower)
{
	const float r = TowerReach(tower);
	const float s = r * ai.GetTunable("apex_front_site_frac", FRONT_SITE_FRAC);
	return (s < 400.f) ? 400.f : s;
}

// WHAT THE TURRET IS WORTH -- not the fact that a turret is being built.
//
// Score() is value/cost, and the value above it was a constant. Four of
// apexearth's complaints are that one line:
//
//   the map edge ("we need EXTRA defense on the edges to compensate"), rebuilding
//   ("kills whatever we have and then we don't seem to rebuild it with any
//   urgency"), the advanced plant ("the T2 lab dying because it was placed and NO
//   turrets were made anywhere near it") and the heavy tier ("Where's our T2 and
//   T3 defenses?"). A constant value divided by cost makes a 3,500-metal
//   Annihilator score ~18x worse than a 190-metal Beamer, so the line got weaker
//   as the economy grew; and it made empty grass at the map's centre score exactly
//   as high as the wall in front of our own factory.
//
// Three multipliers and one addition, none of them a bare number:
//
//  - WHAT IT DENIES, which is damage AND reach. GetSurfThreat is CircuitAI's own
//    measure, taken RELATIVE to the cheapest turret we would ever place --
//    relative, so FRONT_FENCE_VALUE keeps its calibration and only the ORDERING
//    between tiers changes. It contains no range: CircuitDef.h GetSurfThreat is
//    surfThrDmg * sqrt(health + shield), and surfThrDmg is sqrt(dps) * dmg^0.25.
//    So range is a second, multiplied term. apexearth: "at +50 handicap the t2
//    scorp defense is only worthwhile for a short time. you need the longer range
//    defenses."
//
//    LINEAR in range, not squared: this want holds a LINE, and a turret of range
//    R holds R/Rlight as much of it -- the identical quantity FrontLineSpots
//    already spaces the line by. Squared would value a disc instead, and would
//    promote Cortex's 950-range Doomsday over its 1390-range Persecutor by
//    accident of the damage term. Multiplied by the damage term rather than
//    replacing it, and skipped entirely for a def with no surface gun, so
//    something that outranges everything and kills nothing gains nothing.
//
//    Deliberately not proportional to cost either: value that scales with cost
//    makes score constant and deletes the tier distinction altogether, which is
//    a different bug.
//  - HOW EXPOSED IT IS. Exactly the coverage deficit EdgeSpacing already computes
//    for the line's spacing -- at the wall a point is covered from one side
//    instead of two, so the same threat needs twice the defence there.
//  - WHAT IS BEHIND IT, over what the turret costs.
//  - GROUND WE HAVE JUST BEEN PUSHED OFF, added rather than multiplied so it
//    still lifts a stretch whose other terms are all small. A position that ate a
//    turret has proved it is worth defending.
//
// The reference is the metal a raid would take off us if it got through -- an
// advanced plant is ~2,000 -- so the multiplier is ~2x with one behind the line.
const float DEF_ASSET_REF   = 2000.f;
const float DEF_LOSS_WEIGHT = 1.5f;

// CAN THIS TURRET SHOOT BACK AT WHAT IS SHELLING IT.
//
// apexearth, given two candidate reasons why range matters to him -- (1) artillery
// shells a short turret from outside its reach, so its DPS never happens, (2) a
// longer turret covers more line: "1 and 2 here are correct. but 1 is the biggest
// issue. they can't even hit the things that cna see them and easily kill them."
//
// That is why threat-per-metal flatters the Scorpion. corvipe reaches 730 and
// scores nearly double a 1,390-range Persecutor on damage and cost alone, while
// armmerl and corvroc -- BAR's own description, "Stealthy Rocket Launcher - good
// vs. static defense" -- shell it from 1,300.
//
// Neither input is a constant standing in for the enemy. HOW FAR A BESIEGER
// REACHES is the longest range among the game's own besieging defs, resolved by
// name. HOW MUCH IT MATTERS is GetEnemyCost(ARTY) -- what we have actually seen.
//
// The static siege guns are deliberately NOT in the list: nothing we would put on
// a line answers a 4,650-range armbrtha or a 4,950-range corint, and including
// them would drive every turret's factor to ~0.08 and delete defence outright.
//
// DELIBERATELY NOT NORMALISED against the light turret. Normalising restores the
// light turret to 1.0 but inflates every heavy turret 5-9x, which drives the fence
// want hard against mex upgrades -- measured on paper before this shipped. Left as
// it is, the factor sits in [1-s, 1] and can only ever LOWER a turret's value, so
// this cannot be the thing that grows defence spend. Do not "tidy" it.
const float SIEGE_SOFT = 2.f;
float gSiegeReach = -1.f;
float gSiegeRef   = -1.f;

float SiegeReach()
{
	if (gSiegeReach >= 0.f)
		return gSiegeReach;   // defs do not change during a game
	array<string> guns;
	guns.insertLast("armmart");  guns.insertLast("cormart");
	guns.insertLast("legmed");   guns.insertLast("armmerl");
	guns.insertLast("corvroc");  guns.insertLast("corhrk");
	float far = 0.f;
	float cheapest = 0.f;
	for (uint i = 0; i < guns.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(guns[i]);
		if (d is null)
			continue;
		const float r = d.GetMaxRange();
		if (r > far)
			far = r;
		if ((d.costM > 0.f) && ((cheapest <= 0.f) || (d.costM < cheapest)))
			cheapest = d.costM;
	}
	gSiegeReach = far;
	gSiegeRef = cheapest;
	return gSiegeReach;
}

// HOW SIEGED WE ARE, saturating rather than proportional. Their artillery does not
// have to be most of their army for a short turret to be worthless -- one
// Ambassador kills a Scorpion for free -- so this is arty/(arty + one besieger's
// cost), which reads 0.5 at a single cheapest-besieger's worth and 0.75 at three.
// The reference is that def's own costM, read rather than typed.
//
// UNKNOWN READS AS ZERO PENALTY, and that is the safe direction here rather than a
// breach of the unknown-is-never-none rule -- it is not a bug. This term only ever
// REDUCES value, so an unscouted enemy keeps the cheap turrets available, which is
// what was asked for: a Scorpion is genuinely fine against raiders. Suppressing
// them on a guess is the expensive error; keeping them is the cheap one.
float SiegeFraction()
{
	SiegeReach();
	if (gSiegeRef <= 0.f)
		return 0.f;
	const float arty = aiEnemyMgr.GetEnemyCost(Unit::Role::ARTY.type);
	if (arty <= 0.f)
		return 0.f;
	return arty / (arty + gSiegeRef);
}

// 1.0 when we out-reach the besieger, decaying smoothly as we fall short --
// squared, because both the share of the engagement in which we can reply and the
// time we survive under fire fall with the shortfall. CLIPPED at 1: once we can
// reach them, extra reach is the LINE term's business, which is what stops the two
// double-counting.
float SiegeFactor(float reach)
{
	const float s = SiegeFraction();
	if (s <= 0.f)
		return 1.f;
	const float far = SiegeReach();
	if (far <= 1.f)
		return 1.f;   // could not read it: no penalty
	float q = reach / far;
	if (q > 1.f)
		q = 1.f;
	return (1.f - s) + s * pow(q, ai.GetTunable("apex_siege_soft", SIEGE_SOFT));
}

float TowerDenial(CCircuitDef@ tower)
{
	if (tower is null)
		return 1.f;
	CCircuitDef@ light = SideDef3("armllt", "corllt", "leglht");
	const float t = tower.GetSurfThreat();
	const float b = (light is null) ? 0.f : light.GetSurfThreat();
	if ((t <= 0.f) || (b <= 0.f))
		return 1.f;   // no surface gun: no credit at all, range included
	float v = t / b;
	const float lr = LightTowerRange();
	const float tr = TowerReach(tower);
	if ((lr > 0.f) && (tr > lr))
		v *= tr / lr;
	// ...and how much of that damage actually lands on what is shooting at us.
	v *= SiegeFactor(tr);
	return v;
}

// The expensive things a raid actually wants, valued at what losing them costs.
// Each resolves through SideDef3 so Armada, Cortex and Legion all answer, and
// GetOwnUnitsOfDef is position-scoped so this is "behind THIS point", not a
// global tally.
float AssetsBehind(const AIFloat3& in at, float radius)
{
	array<CCircuitDef@> defs;
	defs.insertLast(Factory::AdvCounterpart());
	defs.insertLast(SideDef3("armshltx", "corgant", "leggant"));
	defs.insertLast(SideDef3("armfus", "corfus", "legfus"));
	defs.insertLast(SideDef3("armafus", "corafus", "legafus"));
	float m = 0.f;
	for (uint i = 0; i < defs.length(); ++i) {
		if (defs[i] is null)
			continue;
		array<CCircuitUnit@>@ ours = ai.GetOwnUnitsOfDef(defs[i], at, radius);
		if (ours is null)
			continue;
		m += float(ours.length()) * defs[i].costM;
	}
	return m;
}

float DefenceValue(CCircuitDef@ tower, const AIFloat3& in at, float span)
{
	float v = TowerDenial(tower);
	v *= Military::EdgeExposure(at, span);
	v *= 1.f + AssetsBehind(at, span)
			/ ai.GetTunable("apex_def_asset_ref", DEF_ASSET_REF);
	v += ai.GetTunable("apex_def_loss_weight", DEF_LOSS_WEIGHT)
			* Military::FenceLostNear(at, span);
	return v;
}

// COVERING AN EXTRACTOR, as a WANT rather than as a rule that places its own
// tower. apexearth: "do the consolidation."
//
// MexGuard's REASON was always sound -- a bare extractor is free metal for one
// raider -- and it was its PLACEMENT that produced blobs: it chose a mex, then a
// site next to it, with no reference to anything else we were building. Here the
// reason becomes a proposal that competes with the line on value, and one
// placement path serves both.
//
// A mex with nothing in firing range of it outranks a mex that merely wants a
// second turret, which is what makes cover spread before it thickens.
// A BARE MEX IS HIGH PRIORITY, and the value says why rather than asserting it.
// apexearth: "A mex with no turret in range to defend it is a high priority
// target for building a turret to defend that area."
//
// Everything else in this file is valued in metal per second, so this is too: an
// extractor makes 1.8/s (armmex, read from the defs -- the same figure
// MEXUP_INCOME_GAIN is derived against), and an uncovered one is that income plus
// its 620 metal standing in front of anything that wanders past. The turret is 85.
//
// Scaled by exposure, because a bare extractor on the front is raided and one
// behind the base mostly is not -- FrontT is 0 at home and 1 at the enemy, the
// same measure every other positional rule uses. At home this scores about four
// times a mex upgrade per metal; on the front, twelve.
const float MEX_INCOME_AT_RISK = 1.8f;
const float MEX_EXPOSURE_MULT  = 3.0f;

Want@ MexCoverWant(CCircuitUnit@ unit)
{
	CCircuitDef@ mex = Builder::MexDef();
	if ((mex is null) || (mex.count <= 0))
		return null;
	array<CCircuitUnit@>@ mine = ai.GetOwnUnitsOfDef(mex, Builder::gHomePos, 0.f);
	if ((mine is null) || (mine.length() == 0))
		return null;

	const AIFloat3 me = unit.GetPos(ai.frame);
	const float reach = ai.GetTunable("apex_front_reach", 2200.f);
	AIFloat3 best;
	bool have = false;
	float bestD = 0.f;
	for (uint i = 0; i < mine.length(); ++i) {
		if (mine[i] is null)
			continue;
		const AIFloat3 at = mine[i].GetPos(ai.frame);
		if (!OnMap(at))
			continue;
		if (Builder::DefenceWithin(at, Builder::MEX_IN_RANGE) > 0)
			continue;                       // already covered
		const float d = me.distance2D(at);
		if (d > reach)
			continue;
		if (Builder::ThreatFor(unit, at) > Builder::CON_THREAT_VETO)
			continue;
		if (Builder::DefenceTaskNear(at, Builder::MEX_IN_RANGE))
			continue;
		if (!have || (d < bestD)) {
			bestD = d;
			best = at;
			have = true;
		}
	}
	if (!have)
		return null;

	CCircuitDef@ tower = Builder::MexGuardTower(unit, best);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;
	if (!Military::DefenceAllowedAt(best))
		return null;
	AIFloat3 site = ai.FindBuildSiteNear(tower, best, Builder::MEX_GUARD_RADIUS);
	if (!OnMap(site) || Builder::TooCrowded(site))
		return null;

	Want@ w = Want();
	w.kind = "fence";
	w.value = MEX_INCOME_AT_RISK
			* (1.f + MEX_EXPOSURE_MULT * Builder::FrontT(best));
	w.cost = tower.costM;
	w.pos = site;
	@w.def = tower;
	w.needsAdvCon = false;
	return w;
}

// ANSWERING THEIR AIR, over something worth answering it over.
//
// CheapAA and HeavyAA placed at the CONSTRUCTOR'S OWN POSITION, which is how a
// third of the rearward blobs happened -- the turret went wherever a builder was
// standing. The sizing they did is kept exactly: the enemy's air value against
// what the TEAM already holds, discounted because AA out-trades aircraft per
// metal, with a per-base deterrence floor. Only the position changes: over an
// extractor, which is what their air is actually hunting.
const float AIR_COVER_VALUE = 0.8f;

// AN ORDER IS NOT A TURRET, AND EVERY READ BELOW WAS FINISH-ONLY.
//
// CCircuitAI::GetOwnUnitsOfDef skips u->GetUnit()->IsBeingBuilt(), so a turret we
// have already started does not count as cover; Military::gFencePos is filled from
// the FENCE finished handler, so it does not either. Between "ordered" and
// "finished" this want sees the ground it just claimed as bare, and every builder
// asking in that window gets the same answer.
//
// Builder::gDigOrderPos exists for exactly this and AA never used it. Same shape,
// scoped to AA so an AA order cannot suppress a ground tower or the reverse.
const int AA_ORDER_TTL = 90 * SECOND;
array<AIFloat3> gAAOrderPos;
array<int>      gAAOrderAt;

void NoteAAOrder(const AIFloat3& in pos)
{
	gAAOrderPos.insertLast(pos);
	gAAOrderAt.insertLast(ai.frame);
}

// Standing AA plus AA still on order, within radius. Expired entries drop as they
// are walked: a task can be aborted and there is no completion hook to clear it.
uint AACoverNear(CCircuitDef@ aa, const AIFloat3& in at, float radius)
{
	array<CCircuitUnit@>@ ours = ai.GetOwnUnitsOfDef(aa, at, radius);
	uint n = (ours is null) ? 0 : ours.length();
	for (int i = int(gAAOrderAt.length()) - 1; i >= 0; --i) {
		if (ai.frame - gAAOrderAt[i] > AA_ORDER_TTL) {
			gAAOrderAt.removeAt(i);
			gAAOrderPos.removeAt(i);
		} else if (gAAOrderPos[i].distance2D(at) <= radius) {
			++n;
		}
	}
	return n;
}

Want@ AirCoverWant(CCircuitUnit@ unit)
{
	// AirThreatSeen, not GetEnemyCost(AIR): air constructors and air scouts carry
	// the AIR role, so the raw cost reads enemy ECONOMY as aircraft and sized the
	// turret count off it. The army mix was corrected for this; this was not.
	const float enemyAir = Military::AirThreatSeen();
	CCircuitDef@ aa = Builder::AADefFor(unit);
	if ((aa is null) || !aa.IsAvailable(ai.frame))
		return null;
	// NO AIR SEEN, NO AA. Letting the deterrence floor stand before any sighting
	// was tried and put three SAMs in the base against an enemy with no aircraft.
	// The floor still applies, but only once air exists to deter.
	if (enemyAir < 1.f)
		return null;
	// OUR OWN BASIC COVER FIRST, THE SIDE'S TOP-UP SECOND. The floor is what stops a
	// base having nothing overhead, so it is never charged against the team budget;
	// the budget bounds what we hold BEYOND it. Counted over both tiers -- this read
	// aa.count, the count of one def, so a switch from Thistle to SAM re-opened the
	// floor and bought two more.
	const int want = Builder::AAWantedNow(unit, enemyAir);
	if (Military::OwnStaticAA() < uint(Builder::AA_MIN)) {
		// basic cover for this player, placed by the loop below
	} else if (Military::TeamAA() >= float(want)) {
		return null;
	}

	// Over an extractor rather than under the builder's feet.
	CCircuitDef@ mex = Builder::MexDef();
	if ((mex is null) || (mex.count <= 0))
		return null;
	array<CCircuitUnit@>@ mine = ai.GetOwnUnitsOfDef(mex, unit.GetPos(ai.frame),
			ai.GetTunable("apex_front_reach", 2200.f));
	if ((mine is null) || (mine.length() == 0))
		return null;
	// The turret's own reach is both the cover radius and the value's span, so a
	// SAM covers more extractors than a Thistle and is valued over more of them.
	// TowerReach, not GetMaxRange: every range read in this file goes through the
	// clamp, so no def carrying an interceptor can set a cover radius. A no-op for
	// the AA defs themselves -- 765 to 1,125 against a 2,610 cap.
	const float span = TowerReach(aa);
	const AIFloat3 me = unit.GetPos(ai.frame);
	AIFloat3 best;
	bool have = false;
	uint fewest = 0;
	float bestD = 0.f;
	uint bare = 0;
	for (uint i = 0; i < mine.length(); ++i) {
		if (mine[i] is null)
			continue;
		const AIFloat3 at = mine[i].GetPos(ai.frame);
		if (!OnMap(at) || Builder::TooCrowded(at))
			continue;
		const uint near = AACoverNear(aa, at, span);
		if (near == 0)
			++bare;
		if (near > 0)
			continue;               // covered, or already spoken for
		// NEAREST OF THE BARE ONES. Every candidate that survives the filter has a
		// count of zero, so `!have || near < fewest` picked whichever extractor came
		// first out of GetOwnUnitsOfDef -- the same one for every builder in the
		// base, every call, until one of them finished. Distance is what makes two
		// builders standing in different places choose differently.
		const float d = me.distance2D(at);
		if (!have || (near < fewest) || ((near == fewest) && (d < bestD))) {
			fewest = near;
			bestD = d;
			best = at;
			have = true;
		}
	}
	if (!have)
		return null;
	if (!Military::DefenceAllowedAt(best))
		return null;
	AIFloat3 site = ai.FindBuildSiteNear(aa, best, Builder::MEX_GUARD_RADIUS);
	if (!OnMap(site))
		return null;

	// WHAT THIS PATCH OF SKY IS WORTH, not the fact that AA is wanted somewhere.
	// The value was a bare constant, and it logged as aa=0.0051 in every sample of
	// a 40-minute game: a base with no AA at all proposed exactly what a base with
	// nine proposed, so whoever asked first spent the whole team's allowance.
	//
	// `mine` is scoped to the builder, so `uncovered` is a LOCAL reading -- the
	// builder standing at the base with nothing overhead proposes at ~1.0 and the
	// one standing in the blob proposes at ~0.1. DefenceValue is the same function
	// the front line uses; for an AA def TowerDenial returns 1.0 (no surface gun),
	// so what it contributes here is exposure, what is parked behind the point, and
	// whether we have recently lost a tower there.
	const float uncovered = float(bare) / float(mine.length());

	Want@ w = Want();
	w.kind = "aa";          // its own budget row; Act() handles it as a fence
	w.value = AIR_COVER_VALUE * uncovered * DefenceValue(aa, site, span);
	w.cost = aa.costM;
	w.pos = site;
	@w.def = aa;
	w.needsAdvCon = false;
	w.have = int(fewest);
	return w;
}

Want@ FrontDefenceWant(CCircuitUnit@ unit)
{
	FenceSweep();
	// THE LINE IS SPACED BY THE TURRET'S OWN RANGE. apexearth: "a line of turrets
	// are needed, all within range of each other's firing radius, so no 'leaks'
	// can get through." So the def is chosen FIRST -- it decides how far apart the
	// line's positions are -- and a Rattlesnake line is correctly sparser than a
	// Beamer line rather than both being a flat 700 elmos.
	CCircuitDef@ tower = Builder::FrontTower(unit, unit.GetPos(ai.frame));
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;
	// TowerReach, not GetMaxRange: an anti-nuke's interceptor reports 72,000, and
	// this number is both the line's spacing and the radius cover is counted over.
	float span = TowerReach(tower);
	if (span < 200.f)
		span = 200.f;   // a def with no usable range must not collapse the line
	// OVERLAP, DON'T JUST TOUCH. apexearth: "you'll want to make sure they overlap
	// by ~20% on that firing range circle." At spacing == range the neighbour sits
	// exactly on the edge of the circle, so anything walking the seam is engaged
	// by one turret at its worst range and by nothing else. Pulling the spacing in
	// by a fifth means every point on the line is covered by two.
	const float overlap = ai.GetTunable("apex_front_overlap", 0.2f);
	const float spacing = span * (1.f - overlap);

	array<AIFloat3> line;
	// `span` is the turret's own range, which is what the edge-density correction
	// in FrontLineSpots needs to know: the deficit it corrects is measured in
	// turret ranges from the map edge, not in elmos.
	if (!Military::FrontLineSpots(line, spacing, span) || (line.length() == 0))
		return null;

	// A TASK NOBODY CAN REACH IS NEVER ASSIGNED TO ANYONE. Measured: of 235 front
	// orders across two games, 7 became towers and every single failure was still
	// on the books 90 seconds later with NO worker on it -- not dropped, not
	// killed, just never picked up. The builder manager elects units onto tasks by
	// its own cost-and-distance ranking, so a request 3,000 elmos away loses to
	// every nearer piece of work, forever, however good the position is.
	//
	// So the Brain asks the builder in front of it to cover the stretch of line in
	// front of IT, rather than the best point on the whole curve.
	const AIFloat3 me = unit.GetPos(ai.frame);
	const float reach = ai.GetTunable("apex_front_reach", 2200.f);
	AIFloat3 best;
	bool have = false;
	uint fewest = 0;
	float bestDist = 0.f;
	for (uint i = 0; i < line.length(); ++i) {
		if (!OnMap(line[i]))
			continue;
		const float d = me.distance2D(line[i]);
		if (d > reach)
			continue;
		// Never send a builder somewhere it cannot survive to finish. apexearth:
		// "what is the point in trying to make a tower that can never be built?"
		if (Builder::ThreatFor(unit, line[i]) > Builder::CON_THREAT_VETO)
			continue;
		// Already ordered here: a want that re-proposes every call enqueued 101
		// towers for 15 that got built, and each unassigned task holds its slot
		// for 300 seconds against the engine's budget.
		if (Builder::DefenceTaskNear(line[i], spacing))
			continue;
		// A gap is a stretch of line with nothing in range of it.
		const uint cover = Military::FenceCountNear(line[i], span);
		// Least-covered stretch first -- cover spreads along the line before it
		// thickens anywhere on it -- and the nearer of two equally bare stretches,
		// so the walk is not the cost.
		if (!have || (cover < fewest) || ((cover == fewest) && (d < bestDist))) {
			fewest = cover;
			bestDist = d;
			best = line[i];
			have = true;
		}
	}
	if (!have)
		return null;
	if (!Military::DefenceAllowedAt(best))
		return null;

	// A POINT ON A CURVE IS NOT A BUILD SITE. Every other placement in this AI
	// runs its position through FindBuildSiteNear first; this one handed the raw
	// sample straight to Enqueue. The samples are geometry -- fourteen steps along
	// a bearing -- so they land on slopes, in water and inside existing buildings
	// as often as not.
	best = ai.FindBuildSiteNear(tower, best, FrontSiteSearch(tower));
	if (!OnMap(best))
		return null;

	// HOW MUCH THE LINE IS WORTH RIGHT NOW, rather than a constant. A line with
	// nothing on it is the most valuable thing a builder can be doing; a line
	// already covered end to end is worth almost nothing, and should lose to a mex
	// upgrade without anyone having to write a rule saying so. That is the whole
	// point of the want being ranked instead of sitting in the pipeline.
	uint bare = 0;
	for (uint i = 0; i < line.length(); ++i) {
		if (OnMap(line[i]) && (Military::FenceCountNear(line[i], span) == 0))
			++bare;
	}
	const float uncovered = (line.length() > 0)
			? (float(bare) / float(line.length())) : 0.f;

	Want@ w = Want();
	w.kind = "fence";
	w.value = FRONT_FENCE_VALUE * uncovered * DefenceValue(tower, best, span);
	w.cost = tower.costM;
	w.pos = best;
	@w.def = tower;
	w.needsAdvCon = false;
	w.have = int(fewest);   // a stretch of line already covered is worth less
	return w;
}

// The one want that is executed today. Everything else is proposed and logged so
// the ranking can be read before behaviour is handed to it.
Want@ MexUpgradeWant(CCircuitUnit@ unit)
{
	CCircuitDef@ moho = SideDef3("armmoho", "cormoho", "legmoho");
	if ((moho is null) || !moho.IsAvailable(ai.frame))
		return null;
	CCircuitDef@ mex = SideDef3("armmex", "cormex", "legmex");
	if ((mex is null) || (mex.count <= 0))
		return null;

	// Nearest extractor of ours that the moho out-yields. GetOwnUnitsOfDef is
	// the authoritative "ours" answer -- a register of our own drifted to 4
	// entries on a side holding 150.
	const AIFloat3 here = unit.GetPos(ai.frame);
	array<CCircuitUnit@>@ mine = ai.GetOwnUnitsOfDef(mex, here, MEXUP_REACH);
	if ((mine is null) || (mine.length() == 0))
		return null;

	CCircuitUnit@ best = null;
	float bestDist = MEXUP_REACH;
	for (uint i = 0; i < mine.length(); ++i) {
		if (mine[i] is null)
			continue;
		const AIFloat3 at = mine[i].GetPos(ai.frame);
		if (!OnMap(at))
			continue;
		const float d = here.distance2D(at);
		if (d < bestDist) {
			bestDist = d;
			@best = mine[i];
		}
	}
	if (best is null)
		return null;

	Want@ w = Want();
	w.kind = "mexup";
	// A moho roughly triples a mex's extraction. Expressed as metal/second so it
	// is comparable with a reactor's, rather than as a unitless preference.
	w.value = MEXUP_INCOME_GAIN;
	w.cost = moho.costM;
	w.pos = best.GetPos(ai.frame);
	@w.def = moho;
	w.needsAdvCon = true;
	return w;
}

// A want the Brain does not execute itself: it names the rule that does, and
// Decide() calls that rule only if this want wins. The rule keeps its own
// preconditions -- this decides ORDER, not eligibility.
Want@ Simple(string kind, float value, CCircuitDef@ def, bool advOnly = true)
{
	if ((def is null) || !def.IsAvailable(ai.frame))
		return null;
	Want@ w = Want();
	w.kind = kind;
	w.value = value;
	w.cost = def.costM;
	w.have = def.count;
	@w.def = def;
	w.needsAdvCon = advOnly;
	return w;
}

// Run the rule behind a want. Returns null when its own preconditions refuse,
// in which case Decide falls through to the next-ranked want.
IUnitTask@ Execute(const string& in kind, CCircuitUnit@ unit)
{
	if (kind == "gantry")
		return Builder::SurplusGantry(unit);
	if (kind == "silo")
		return Builder::NukeSilo(unit);
	if (kind == "pulsar")
		return Builder::Pulsar(unit);
	if (kind == "pinpoint")
		return Builder::Pinpointer(unit);
	if (kind == "energy") {
		// ALWAYS BE BUILDING ENERGY. apexearth: "The rule is really simple. Always
		// be building energy. Build converters if we are wasting energy. If we are
		// full of both energy and metal then making more energy becomes less
		// important."
		//
		// All three clauses are in Decide -- the want is proposed every tick, the
		// converter want is gated on EnergyWasting, and ECO_SATED_MULT damps both
		// when the banks are full. The first one has never actually fired: this
		// called HomeEnergy, which returns null for any constructor that is not in
		// the HOME crew (Crew::RoleOf), so the highest-value want in the ranking
		// silently did nothing for every other builder. Measured against the
		// pre-Brain build at minute 14: energy produced 206,124 -> 170,830.
		//
		// HomeEnergy no longer refuses on crew role, so it answers for any
		// builder and keeps the ladder that tiers wind -> advanced solar ->
		// fusion. The fallback below is for the cases it still declines -- a
		// naval builder with no reachable site, a def not yet available -- and
		// places on the same base grid so it lands in the eco band rather than
		// wherever the unit happens to be standing.
		IUnitTask@ home = Builder::HomeEnergy(unit);
		if (home !is null)
			return home;
		if (Builder::EnergyWasting())
			return null;   // the converter want owns this case
		// A base with a reactor standing does not want a 20-energy panel. This
		// fallback is for the cases HomeEnergy cannot PLACE, not the ones where
		// it declined on purpose -- otherwise it just swaps the turbine for a
		// solar and the ladder still never climbs.
		if (Builder::HaveReactor())
			return null;
		CCircuitDef@ gen = Builder::SolarDef();
		if ((gen is null) || !gen.IsAvailable(ai.frame))
			return null;
		AIFloat3 spot;
		if (!Base::Spot(unit, gen, Base::ECO, spot))
			spot = Builder::gHomePos;
		if (!OnMap(spot))
			return null;
		return aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::ENERGY,
				Task::Priority::NORMAL, gen, spot, SQUARE_SIZE * 8));
	}
	if (kind == "convert")
		return Builder::EnergyConverter(unit);
	if (kind == "nano")
		return Builder::EcoNano(unit);
	if (kind == "frontnano")
		return Builder::FrontNano(unit);
	return null;
}

// AiMakeTask is a RE-ELECTION, not always a request for work:
// IBuilderTask::Reevaluate calls it on every task update for a builder not yet
// in build range, and reassigns only on a different build type. A rule that
// Enqueues before returning therefore leaks one orphan task per update, and
// reassignment also restarts the unit's pending path query.
bool AskingForNewWork(CCircuitUnit@ unit)
{
	if (unit is null)
		return false;
	IUnitTask@ t = unit.task;
	if (t is null)
		return true;
	// GetType() returns int, and Task::Type will not implicitly convert -- compare
	// against the enum values rather than storing one.
	return (t.GetType() == Task::Type::IDLE)
		|| (t.GetType() == Task::Type::NIL)
		|| (t.GetType() == Task::Type::WAIT);
}

// Rank, log, and act on the best want whose rule accepts.
IUnitTask@ Decide(CCircuitUnit@ unit, bool isAdvCon)
{
	if (!AskingForNewWork(unit))
		return null;
	Clear();
	// THE BRAIN WAS INERT FOR THE WHOLE EARLY GAME.
	//
	// This read `if (!isAdvCon) return null;`, and isAdvCon is cost >= 300, i.e.
	// a T2 constructor. Measured: conT2 is 0 at minute 12 in every game sampled,
	// and `apex: brain wants=` appears ZERO times in a 12-minute infolog. So the
	// Wants faculty -- the thing that is supposed to rank what our metal buys --
	// did not run at all until an advanced constructor existed, which is after
	// the window where our economy actually falls behind.
	//
	// Only some wants genuinely need an advanced builder: a moho, a gantry, a
	// silo. Energy, converters and nano turrets are ordinary T1 work. So the test
	// moves from the whole function to the individual want, which is what
	// needsAdvCon was for.

	// NOTHING OPTIONAL BEFORE T2 EXISTS.
	//
	// apexearth, watching a 4v4 at +25: "something's going wrong this game where
	// our guys are not going to t2." The lead logged "building advanced plant
	// coravp" fifty times with haveT2 still 0 -- the plant was requested over and
	// over while constructors went to converters, nanos and reactors, all of
	// which this session had just ungated for every player. Each was individually
	// reasonable and together they starved the one building that unlocks the
	// rest.
	//
	// Before an advanced factory stands, the only thing worth a constructor is
	// expansion. This is the 2026-08-01 displacement finding arriving through the
	// Brain rather than through the ladder.
	const bool preT2 = !Factory::gHaveT2;

	Propose(MexWant(unit));
	Propose(FrontDefenceWant(unit));
	Propose(MexCoverWant(unit));
	Propose(AirCoverWant(unit));
	Propose(MexUpgradeWant(unit));
	// The optional class. Costs are read from the defs so a score means
	// something; where a def is missing the want is simply not proposed.
	// ALWAYS MAKE ENERGY, AND CONVERT WHEN IT SPILLS -- as scores, so they can
	// be compared rather than merely obeyed. apexearth: "we had built custom eco
	// logic... always make energy, and if max energy make energy converters."
	// ALWAYS, not only when already broke. The rule this implements is "always
	// make energy, and if max energy make energy converters" -- but the code only
	// proposed energy `if (isEnergyStalling)`, which is the state where the grid
	// has ALREADY run out. So the Brain never grew energy ahead of demand; growth
	// happened only through rules that bypass this ranking entirely, each of which
	// put down a basic collector. apexearth: "we make too many basic solars and
	// not enough advanced solars."
	//
	// A stall is urgency, so it stays a multiplier rather than the gate.
	// ...BUT NOT WHILE IT IS SPILLING. The rule is "always be building energy;
	// build converters if we are wasting energy" -- two clauses, and proposing
	// both at once means the generator want keeps winning and the spill grows.
	// Measured when this was unconditional: energy produced 315,333 per player
	// against stock's 169,414, of which 180,306 was WASTED, while metal fell to
	// 10,331 and the trade ratio collapsed to 0.11. More generators is the answer
	// to a shortage, never to a surplus.
	if (!Builder::EnergyWasting()) {
		Want@ e = Simple("energy",
				ENERGY_VALUE * (aiEconomyMgr.isEnergyStalling ? ENERGY_STALL_MULT : 1.f),
				Builder::SolarDef(), false);
		if (e !is null) {
			// NOT decayed by how many we hold. `/(1 + have)` is right for "one
			// more Pinpointer" and wrong for energy: demand comes from what the
			// base CONSUMES, and it does not fall because a collector already
			// stands. The stall branch used to zero this by hand, which was the
			// same admission in one special case.
			e.have = 0;
			Propose(e);
		}
	}
	// NO preT2 GATE. Spilling energy is spilling energy, and a converter is 1
	// metal to build -- the cheapest metal in the game while the grid overflows.
	// Blocking this before an advanced plant existed threw the surplus away in
	// exactly the window our economy is weakest: measured 22,000-28,000 energy
	// wasted per side by minute 10.
	// BOUNDED BY THE SPILL, NOT BY A SCORE. A converter costs 1 metal, and
	// Score() deliberately skips the per-metal division below a cost of 1, so it
	// ranks 1.0 against a reactor's 0.003 and wins every single tick. That is not
	// wrong as economics -- while energy overflows it IS the best metal-per-metal
	// in the game -- but it has no natural stopping point, so the bound has to be
	// the thing it feeds on: one converter draws 70 energy/second, so the grid
	// supports income/70 of them and no more.
	// THE ADVANCED CONVERTER, WHENEVER WE CAN BUILD ONE. apexearth: "spacing also
	// matters... that cheap e converter takes up a lot of room and is very
	// fragile, so the advanced version is almost always better." Nine armmakr to
	// match one armmmkr's 600-energy draw is nine footprints in the eco band and
	// nine things that die to one shell. This proposed the small one by name.
	if (Builder::EnergyWasting()) {
		CCircuitDef@ big = Builder::BigConvDef(unit);
		const bool useBig = isAdvCon && (big !is null) && big.IsAvailable(ai.frame);
		CCircuitDef@ conv = useBig ? big : Builder::SmallConvDef(unit);
		const float draw = useBig ? CONVERT_DRAW_BIG : CONVERT_DRAW;
		const int convRoom = int(aiEconomyMgr.energy.income / draw);
		if ((conv !is null) && (conv.count < convRoom)) {
			Want@ c = Simple("convert", CONVERT_VALUE * (useBig ? BIG_CONV_VALUE : 1.f),
					conv, false);
			if (c !is null) {
				c.have = 0;   // demand is the spill, not how many already stand
				Propose(c);
			}
		}
	}

	// Spend the surplus rather than growing it further.
	if (!preT2 && (EcoSated() || aiEconomyMgr.isMetalFull))
		Propose(Simple("nano", NANO_VALUE, SideDef3("armnanotc", "cornanotc", "legnanotc"), false));
	// ON by default. Attribution showed the income gate, not these, caused the
	// army drop -- and K/D was the one number that went UP with them (1.49 ->
	// 1.54). apexearth: "notice how our KD went up with the nanodefense. Maybe
	// we're just building them a little bit too early, or making too many at
	// once. Probably a good thing to have on, just be reasonable about it."
	// So: kept, later and fewer (see FRONT_NANO_* in builder/nano.as).
	if (!preT2 && (ai.GetTunable("apex_front_nano", 1.f) > 0.f))
		Propose(Simple("frontnano", FRONT_NANO_VALUE, SideDef3("armnanotc", "cornanotc", "legnanotc"), false));

	if (!preT2) {
	Propose(Simple("gantry", GANTRY_VALUE, SideDef3("armshltx", "corgant", "leggant")));
	Propose(Simple("silo", SILO_VALUE, SideDef3("armsilo", "corsilo", "legsilo")));
	Propose(Simple("pulsar", PULSAR_VALUE, SideDef3("armanni", "cordoom", "legstarfall")));
	Propose(Simple("pinpoint", PINPOINT_VALUE, SideDef3("armtarg", "cortarg", "legtarg")));
	}

	if (gWants.length() == 0)
		return null;

	// Descending by score, first rule that accepts wins.
	//
	// Ranking every under-budget category ahead of every at-budget one was tried
	// 2026-08-12 and measured WORSE: fence orders 19 -> 6, mexes 10-19 -> 5-11.
	// Early on nothing has been built, so every category reads under target and
	// the partition decides nothing while destabilising the order. Coverage
	// scaling in the want's own value is the lever that works instead.
	array<Want@> order = gWants;
	for (uint i = 0; i < order.length(); ++i) {
		for (uint j = i + 1; j < order.length(); ++j) {
			if (order[j].Score() > order[i].Score()) {
				Want@ tmp = order[i];
				@order[i] = order[j];
				@order[j] = tmp;
			}
		}
	}

	if (ai.frame >= gNextBrainLog) {
		gNextBrainLog = ai.frame + 30 * SECOND;
		string line = "apex: brain wants=" + order.length();
		for (uint i = 0; i < order.length(); ++i)
			line += " | " + order[i].kind + "=" + formatFloat(order[i].Score(), "", 0, 4);
		AiLog(Factory::T() + line);
	}

	// UPGRADES ARE NOT OPTIONAL SPENDING. If an upgrade is in reach, this
	// constructor's job is the upgrade -- and if the enqueue happens to fail
	// (spot taken, already upgrading), it goes back to the engine's own work
	// rather than starting a Pulsar instead.
	//
	// Measured: with the optional class executing whenever it outranked nothing,
	// picks rose from 13 to 20 per batch and T2 mex share fell 17.6% -> 15.1%.
	// Ranking decides order among optional things; it does not get to displace
	// the economy that pays for them.
	//
	// ONLY AN UPGRADE **THIS** BUILDER COULD DO BLOCKS ANYTHING. The loop below
	// skips a want with needsAdvCon for a builder that is not advanced, and the
	// moho is exactly such a want -- so a T1 constructor was blocked out of the
	// whole optional class by a job it is physically unable to take, leaving it
	// only the two kinds that bypass this test. That is a STOP, not a spend: for
	// an advanced constructor nothing changes, which is the case the measurement
	// above was taken on.
	bool haveMexUp = false;
	for (uint i = 0; i < order.length(); ++i) {
		if (order[i].needsAdvCon && !isAdvCon)
			continue;
		if (order[i].kind == "mexup") {
			haveMexUp = true;
			break;
		}
	}
	// With both banks full the upgrade is no longer the thing standing between
	// us and spending, so it stops blocking everything else.
	if (EcoSated())
		haveMexUp = false;

	for (uint i = 0; i < order.length(); ++i) {
		Want@ w = order[i];
		if (w.needsAdvCon && !isAdvCon)
			continue;   // this one really does need an advanced builder
		// Expansion is never blocked by a pending upgrade: a new extractor is
		// worth five upgrades per metal, and they are not alternatives -- one
		// takes ground, the other improves ground already held.
		//
		// A COVERAGE GAP IS NOT OPTIONAL SPENDING EITHER. apexearth: "if an area
		// lacks coverage then that build order to cover it is much more important
		// than adding defense to some other area that already has coverage."
		//
		// `have` on a defence want is FenceCountNear at the chosen point, so zero
		// means nothing at all is in range of that stretch -- not "thin", bare.
		// Thickening a stretch that already has cover still waits for the upgrade,
		// which is what keeps this from becoming a general exemption.
		const bool gap = ((w.kind == "fence") || (w.kind == "aa")) && (w.have == 0);
		if ((w.kind != "mexup") && (w.kind != "mex") && haveMexUp && !gap)
			continue;
		// "aa" is placed exactly like a fence -- a DEFENCE build task at a chosen
		// site. Only the budget row it is scored against differs.
		if ((w.kind == "fence") || (w.kind == "aa")) {
			// PRIORITY IS WHAT DECIDES WHETHER ANYONE IS EVER SENT.
			// CBuilderManager::MakeBuilderTask, the engine's own elector, skips a
			// candidate whose site is threatened and enemy-influenced -- except
			// when the task is NOW, where its own comment reads "Disregard
			// safety". A front site is threatened and enemy-influenced by
			// definition, so at NORMAL these orders are unelectable and sit on the
			// books forever: measured 48-105 alive with no worker against 1-18
			// aborted.
			const Task::Priority prio = (ai.GetTunable("apex_front_now", 0.f) > 0.f)
					? Task::Priority::NOW : Task::Priority::NORMAL;
			IUnitTask@ t = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
					prio, w.def, w.pos, SQUARE_SIZE * 4));
			if (t !is null) {
				++gFenceOrders;
				if (w.kind == "aa")
					NoteAAOrder(w.pos);
				const float fwd = Military::ForwardFraction(w.pos);
				if (fwd < 0.10f)
					++gFenceNear;
				else if (fwd < 0.25f)
					++gFenceMid;
				else
					++gFenceFar;
				gAimPos.insertLast(w.pos);
				gAimAt.insertLast(ai.frame);
				gAimTask.insertLast(t);
				gAimSeen.insertLast(false);
				if (gFenceOrders <= 3 || (gFenceOrders % 10 == 0)) {
					AiLog(Factory::T() + "apex: brain orders front defence #"
						+ gFenceOrders + " " + w.def.GetName()
						+ " fwd=" + formatFloat(fwd, "", 0, 2)
						+ " aimed near/mid/far=" + gFenceNear + "/" + gFenceMid
						+ "/" + gFenceFar);
				}
				return t;
			}
			continue;
		}
		if (w.kind == "mex") {
			const int spot = aiEconomyMgr.FindOpenMexSpot(unit, unit.GetPos(ai.frame));
			if (spot < 0)
				continue;
			IUnitTask@ t = aiEconomyMgr.EnqueueMexAt(unit, spot);
			if (t !is null) {
				++gMexOrders;
				if (gMexOrders <= 3 || (gMexOrders % 25 == 0)) {
					AiLog(Factory::T() + "apex: brain orders mex #" + gMexOrders
						+ " by " + unit.circuitDef.GetName());
				}
				return t;
			}
			continue;
		}
		if (w.kind == "mexup") {
			// The binding added 2026-08-10. A MEXUP task carries a metal-spot
			// index as well as a position, so the generic Enqueue could not
			// express it -- which is why no rule of ours could order an upgrade.
			IUnitTask@ t = aiBuilderMgr.EnqueueMexUp(w.pos, w.def);
			if (t !is null) {
				++gMexUpOrders;
				if (gMexUpOrders <= 3 || (gMexUpOrders % 25 == 0)) {
					AiLog(Factory::T() + "apex: brain orders mexup #" + gMexUpOrders
						+ " by " + unit.circuitDef.GetName());
				}
				return t;
			}
			continue;
		}
		IUnitTask@ t = Execute(w.kind, unit);
		if (t !is null) {
			if (ai.frame >= gNextPickLog) {
				gNextPickLog = ai.frame + 60 * SECOND;
				AiLog(Factory::T() + "apex: brain picks " + w.kind
					+ " score=" + formatFloat(w.Score(), "", 0, 4));
			}
			return t;
		}
	}
	return null;
}

}  // namespace Brain
