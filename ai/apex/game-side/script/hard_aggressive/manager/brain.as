namespace Brain {

//------------------------------------------------------------------------------
// THE MACRO VIEW. Rules propose; this decides.
//
// The ladder in builder/maketask.as makes POSITION the priority: the first rule
// that returns a task wins. Here a rule states a WANT -- what it would do, what
// that is worth, what it costs -- with no side effects, and Decide() ranks the
// list and acts. docs/18-brain.md describes the design.
//
// Only the mex-upgrade want is enqueued by this file. Every other kind names an
// existing rule in Execute(), which keeps its own preconditions -- the ranking
// decides ORDER, not eligibility. A new want therefore needs a Propose() call
// AND a line in Execute(), or it ranks and can never fire.
//
// Value is metal per second gained, per metal spent -- the one unit every
// economic want can be expressed in. Defence and offence need their own terms
// and are deliberately not here yet.
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
// Above NANO_VALUE on purpose: insurance against a game-ending strike loses to
// nothing recurring, and Score() halves it once the first one stands.
const float ANTINUKE_VALUE = 8.0f;
const float PULSAR_VALUE   = 1.5f;   // area denial near the base
const float PINPOINT_VALUE = 0.5f;   // targeting support, cheap and bounded
// The standing eco rules, as values rather than as "always".
//
// A converter eats 70 energy/s and returns 1 metal/s for ~1 metal to build
// (armmakr.lua), the best metal-per-metal while energy spills. Energy itself
// is URGENT rather than merely valuable when the grid stalls: UpdateEconomyTasks
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
// BOTH BANKS FULL MEANS INCOME IS NOT THE PROBLEM. More income buys nothing when
// neither resource can be stored or spent, so everything economic drops behind
// the things that spend.
const float ECO_SATED_MULT    = 0.25f;
// BUILD POWER IS WHAT A FULL BANK ACTUALLY NEEDS. A nano turret converts banked
// metal back into units at ~7 metal/s of build power for ~300 metal, which beats
// every income want once income is no longer the constraint. Scored high only
// while sated, so it cannot crowd out expansion in a normal game.
const float NANO_VALUE        = 7.0f;
// A front turret repairs instead of producing, so its value is what it keeps
// alive rather than what it builds. Lower than a base nano's build power, and
// it only proposes once there is a front to stand behind.
const float FRONT_NANO_VALUE  = 3.0f;

bool EcoSated()
{
	return aiEconomyMgr.isMetalFull && aiEconomyMgr.isEnergyFull;
}

// ARMY IS NOT THE RESIDUAL. Economy defers when we are losing the army fight,
// the same shape as ECO_SATED_MULT but opposite cause: there the constraint
// moved to build power, here to the front.
//
// Scaled by HOW FAR behind, not switched, so this cannot latch us out of
// expanding. EnemyArmyCost only accumulates on sighting, so an unscouted enemy
// reads small and the multiplier stays near 1 -- ignorance never damps the
// economy.
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
	// land line. They must stay separate budgets, or the air-defence share ends
	// up governing every ground tower. See targets.as.
	if (kind == "aa")
		return AIRDEF;
	if ((kind == "fence") || (kind == "pulsar") || (kind == "silo")
		|| (kind == "pinpoint") || (kind == "antinuke"))
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

	// Metal already standing in this kind (def.count * costM). >= 0 switches
	// Score() to RATIO semantics -- apexearth: "if a nuke silo has a value of 4
	// and nanos are 7... I would expect a 4:7 ratio between nanos and nukes."
	// Scoring value against invested metal makes spend converge to exactly
	// that: each kind's standing metal approaches its share of the values.
	// <0 keeps the legacy have-count scoring for wants whose `have` is not a
	// unit count (fence coverage, mexup, ...).
	float investedM = -1.f;

	// VALUE AS A SPENDING RATIO (invested path) or value-per-metal with
	// per-copy halving (legacy path). The legacy /cost division is skipped on
	// the invested path: cost-normalisation is inherent when the denominator
	// grows by cost with every copy built.
	float Score() const
	{
		float scaled;
		if (investedM >= 0.f) {
			scaled = value / (1.f + investedM
					/ ai.GetTunable("apex_value_norm", 1000.f));
		} else {
			scaled = value / (1.f + float(have));
		}
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
		if (investedM >= 0.f)
			return scaled;
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

// DID THE ORDER BECOME A TOWER? Orders and standing towers are tracked
// separately, so a request that was aimed but never built looks identical, at
// the end of the game, to one that was never aimed forward at all.
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
// ExpansionAlwaysWins (rules_offer.as, deleted 2026-08-14) protected expansion
// by taking the engine's offer whenever it happened to be a mex, which could not
// help when the engine offered something else or nothing. A plain extractor
// yields ~1.8 metal/s for ~50 metal against a moho upgrade's 0.0058/metal and a
// reactor's 0.0034/metal, so expansion outranks both on value alone without
// needing to be hard-coded first in the list.
//
// Any builder, not just an advanced one: taking ground is T1 work.
const float MEX_INCOME_GAIN = 1.8f;   // armmex extraction, read from the defs

Want@ MexWant(CCircuitUnit@ unit)
{
	CCircuitDef@ mex = SideDef3("armmex", "cormex", "legmex");
	if ((mex is null) || !mex.IsAvailable(ai.frame))
		return null;
	// BOUNDED BY BUILD POWER. Every open spot is worth the same, so this want
	// re-proposes for every builder on every call unless capped. One outstanding
	// job per worker is the honest ceiling -- a job nobody can walk to is a slot
	// held for 300 seconds against the engine's economy budget.
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
// Every tower before this was placed by somebody else and merely approved or
// refused here -- MexGuard picked the mex, Fortify picked wherever a
// constructor was standing when it got shot. Here the Brain proposes a
// POSITION: Military::FrontCurve is the influence crossing sampled lane by
// lane, and the pick is the point on it with the least standing cover, so
// cover spreads along the line before it thickens anywhere on it.
//
// Value is deliberately modest -- defence's real currency is threat denied per
// metal, which this file does not yet speak -- so what actually bounds it is
// the DEFENCE category budget from targets.as via BudgetMult.
const float FRONT_FENCE_VALUE = 1.2f;
const float FRONT_FENCE_SPREAD = 700.f;   // how far apart cover counts as spread
// HOW FAR TO LOOK FOR GROUND THE TOWER FITS ON. The samples searched around are
// raw geometry, so they land on slopes, in water and inside buildings, and
// FrontLineSpots is deterministic -- a spot that fails once fails on every call
// for the rest of the game, and failure means the want is silently never
// proposed. Scaled off the tower's own range so the search can reach the
// neighbouring valid ground on the line.
const float FRONT_SITE_FRAC = 0.9f;

// A RANGE READ IS NOT AUTOMATICALLY A GUN'S RANGE. GetMaxRange is the def's
// longest weapon whatever it is for -- an anti-nuke's interceptor reports
// 72,000 elmos, and legrampart carries one. Read unclamped, that range sets the
// line's spacing and the radius cover is counted over, so it can collapse the
// line to a point and zero the want's value. Bounded by the longest real static
// direct-fire gun any faction fields (legperdition, 2,300 elmos) -- anything
// above that is artillery or an interceptor, not a line gun.
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
// Value is three multipliers and one addition, none of them a bare number:
//
//  - WHAT IT DENIES: GetSurfThreat (damage) relative to the cheapest turret we
//    would place, times range LINEARLY (not squared -- this want holds a LINE,
//    and a turret of range R holds R/Rlight of it, the same quantity
//    FrontLineSpots spaces by; squaring would value a disc instead). Skipped
//    entirely for a def with no surface gun, and deliberately not proportional
//    to cost, which would delete the tier distinction.
//  - HOW EXPOSED IT IS: the coverage deficit EdgeSpacing already computes for
//    the line's spacing -- a wall point is covered from one side instead of two.
//  - WHAT IS BEHIND IT, over what the turret costs.
//  - GROUND WE HAVE JUST BEEN PUSHED OFF, added rather than multiplied so it
//    lifts a stretch whose other terms are small without dominating them.
//
// The reference for "what is behind it" is the metal a raid would take off us
// if it got through -- an advanced plant is ~2,000 metal.
const float DEF_ASSET_REF   = 2000.f;
const float DEF_LOSS_WEIGHT = 1.5f;

// CAN THIS TURRET SHOOT BACK AT WHAT IS SHELLING IT. Threat-per-metal alone
// flatters a short-range turret that artillery can shell for free -- corvipe at
// 730 range scores nearly double a 1,390-range Persecutor on damage and cost
// alone. HOW FAR A BESIEGER REACHES is the longest range among the game's own
// besieging defs, resolved by name; HOW MUCH IT MATTERS is GetEnemyCost(ARTY).
//
// Static siege guns are deliberately excluded: nothing we place on a line
// answers a 4,650-range armbrtha, and including them would drive every turret's
// factor to ~0.08 and delete defence outright.
//
// DELIBERATELY NOT NORMALISED against the light turret -- normalising inflates
// every heavy turret 5-9x and drives the fence want hard against mex upgrades.
// The factor stays in [1-s, 1] and can only ever LOWER a turret's value.
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

// HOW SIEGED WE ARE, saturating rather than proportional: arty/(arty + one
// besieger's cost), so a short turret does not need to face most of the enemy
// army to read as worthless.
//
// UNKNOWN READS AS ZERO PENALTY: this term only ever reduces value, so an
// unscouted enemy keeps the cheap turrets available rather than suppressing them
// on a guess.
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
// tower. MexGuard's reason was always sound -- a bare extractor is free metal
// for one raider -- but its placement produced blobs by choosing a site with no
// reference to anything else being built. Here the reason becomes a proposal
// that competes with the line on value, and one placement path serves both.
//
// Valued in metal/second like everything else here: an extractor makes 1.8/s
// (armmex) plus its 620 metal standing exposed against a raid, scaled by
// exposure (FrontT, 0 at home / 1 at the enemy) so a bare mex on the front
// outranks a mex that merely wants a second turret.
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
	if (!Military::DefenceAllowedAt(best, tower))
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
// GetOwnUnitsOfDef skips units still under construction, and Military::gFencePos
// only fills from the FENCE finished handler, so between "ordered" and
// "finished" this want sees the ground it just claimed as bare. Builder::
// gDigOrderPos exists for exactly this and AA never used it; scoped separately
// here so an AA order cannot suppress a ground tower or the reverse.
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
	// Sized off the larger of the smoothed and this-tick reading (AirThreatNow)
	// so a freshly-detected raid is not sized off a stale 0 average while it is
	// still climbing -- see AirThreatNow, airthreat.as.
	const float enemyAirFast = Military::AirThreatNow();
	const float enemyAir = (enemyAirFast > Military::AirThreatSeen())
			? enemyAirFast : Military::AirThreatSeen();
	CCircuitDef@ aa = Builder::AADefFor(unit);
	if ((aa is null) || !aa.IsAvailable(ai.frame))
		return null;
	// NO AIR SEEN, NO AA. Letting the deterrence floor stand before any sighting
	// was tried and put three SAMs in the base against an enemy with no aircraft.
	// The floor still applies, but only once air exists to deter.
	// Gate on the FAST reading, not the 240s-smoothed average: a raid can develop
	// and do its damage well inside that window, and gating on the average left
	// this returning null for nearly the whole of a 19-minute match while airRaw
	// climbed 150->4924 (2026-08-14).
	if (enemyAirFast < 1.f)
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
	if (!Military::DefenceAllowedAt(best, aa))
		return null;
	AIFloat3 site = ai.FindBuildSiteNear(aa, best, Builder::MEX_GUARD_RADIUS);
	if (!OnMap(site))
		return null;

	// WHAT THIS PATCH OF SKY IS WORTH, not the fact that AA is wanted somewhere. A
	// bare constant here let whoever asked first spend the whole team's allowance
	// regardless of coverage.
	//
	// `mine` is scoped to the builder, so `uncovered` is a LOCAL reading: a bare
	// base proposes near 1.0, a blob proposes near 0.1. DefenceValue is the same
	// function the front line uses; TowerDenial returns 1.0 for an AA def (no
	// surface gun), so exposure and what is behind the point are what it adds.
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
	// THE LINE IS SPACED BY THE TURRET'S OWN RANGE. The def is chosen FIRST -- it
	// decides how far apart the line's positions are -- so a Rattlesnake line is
	// correctly sparser than a Beamer line rather than both being a flat spacing.
	CCircuitDef@ tower = Builder::FrontTower(unit, unit.GetPos(ai.frame));
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;
	// TowerReach, not GetMaxRange: an anti-nuke's interceptor reports 72,000, and
	// this number is both the line's spacing and the radius cover is counted over.
	float span = TowerReach(tower);
	if (span < 200.f)
		span = 200.f;   // a def with no usable range must not collapse the line
	// OVERLAP, DON'T JUST TOUCH. At spacing == range a neighbour sits exactly on
	// the edge of the circle, so anything walking the seam is engaged by one
	// turret at its worst range only. Pulling spacing in by a fifth covers every
	// point on the line by two turrets.
	const float overlap = ai.GetTunable("apex_front_overlap", 0.2f);
	const float spacing = span * (1.f - overlap);

	array<AIFloat3> line;
	// `span` is the turret's own range, which is what the edge-density correction
	// in FrontLineSpots needs to know: the deficit it corrects is measured in
	// turret ranges from the map edge, not in elmos.
	if (!Military::FrontLineSpots(line, spacing, span) || (line.length() == 0))
		return null;

	// A TASK NOBODY CAN REACH IS NEVER ASSIGNED TO ANYONE. The builder manager
	// elects units onto tasks by its own cost-and-distance ranking, so a request
	// far from any builder loses to every nearer piece of work, forever, however
	// good the position is. So the Brain asks the builder in front of it to cover
	// the stretch of line in front of IT, rather than the best point on the whole
	// curve.
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
		// Never send a builder somewhere it cannot survive to finish.
		if (Builder::ThreatFor(unit, line[i]) > Builder::CON_THREAT_VETO)
			continue;
		// Already ordered here: a want that re-proposes every call would enqueue
		// many towers for few that get built, each holding its slot for 300
		// seconds against the engine's budget.
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
	if (!Military::DefenceAllowedAt(best, tower))
		return null;

	// A POINT ON A CURVE IS NOT A BUILD SITE. The samples are raw geometry, so
	// they land on slopes, in water and inside existing buildings as often as
	// not -- run through FindBuildSiteNear like every other placement in this AI.
	best = ai.FindBuildSiteNear(tower, best, FrontSiteSearch(tower));
	if (!OnMap(best))
		return null;

	// HOW MUCH THE LINE IS WORTH RIGHT NOW, rather than a constant. A bare line is
	// the most valuable thing a builder can do; a line already covered end to end
	// should lose to a mex upgrade without a separate rule saying so.
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
	w.investedM = float(def.count) * def.costM;  // ratio scoring; see Want
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
	if (kind == "antinuke")
		return Builder::AntiNuke(unit);
	if (kind == "pulsar")
		return Builder::Pulsar(unit);
	if (kind == "pinpoint")
		return Builder::Pinpointer(unit);
	if (kind == "energy") {
		// ALWAYS BE BUILDING ENERGY, CONVERT WHEN IT SPILLS. All three clauses are
		// in Decide -- the want is proposed every tick, the converter want is gated
		// on EnergyWasting, and ECO_SATED_MULT damps both when the banks are full.
		//
		// HomeEnergy answers for any builder, not just the HOME crew, and keeps
		// the ladder that tiers wind -> advanced solar -> fusion. The fallback
		// below is for the cases it still declines -- a naval builder with no
		// reachable site, a def not yet available -- and places on the same base
		// grid so it lands in the eco band rather than wherever the unit happens
		// to be standing.
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
		return Requests::Take(unit, gen, Task::BuildType::ENERGY,
				Task::Priority::NORMAL, spot, 0.f, SQUARE_SIZE * 8);
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
	// THE BRAIN MUST RUN BEFORE T2 EXISTS. Only some wants genuinely need an
	// advanced builder -- a moho, a gantry, a silo. Energy, converters and nano
	// turrets are ordinary T1 work, so the eligibility test lives on the
	// individual want (needsAdvCon), not on the whole function.

	// NOTHING OPTIONAL BEFORE T2 EXISTS. Before an advanced factory stands, the
	// only thing worth a constructor is expansion -- every optional want (nanos,
	// gantries, converter growth) would otherwise compete with the constructor
	// that unlocks T2 itself.
	const bool preT2 = !Factory::gHaveT2;

	Propose(MexWant(unit));
	// Before any factory exists there is exactly one builder in the game -- the
	// commander -- so this gate stops the opening builder walking to a front
	// site instead of requesting the first lab.
	if (Factory::HaveAnyFactory()) {
		Propose(FrontDefenceWant(unit));
		// Same "fence" kind as FrontDefenceWant above; gating only one left the
		// other still able to win the commander's turn pre-lab.
		Propose(MexCoverWant(unit));
	}
	Propose(AirCoverWant(unit));
	Propose(MexUpgradeWant(unit));
	// The optional class. Costs are read from the defs so a score means
	// something; where a def is missing the want is simply not proposed.
	//
	// ALWAYS MAKE ENERGY, CONVERT WHEN IT SPILLS -- as scores rather than gates,
	// so the two compete instead of the energy want only firing once the grid
	// has already run dry. A stall is urgency, so it stays a multiplier rather
	// than the gate, and the energy want is skipped entirely while spilling --
	// proposing both at once just makes the generator keep winning and the spill
	// grow.
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
			e.investedM = -1.f;  // keep the no-decay intent under ratio scoring
			Propose(e);
		}
	}
	// NO preT2 GATE. Spilling energy is spilling energy, and a converter is 1
	// metal to build -- the cheapest metal in the game while the grid overflows.
	// BOUNDED BY THE SPILL, NOT BY A SCORE. Score() skips the per-metal division
	// below a cost of 1, so a converter ranks 1.0 and wins every tick -- correct
	// while energy overflows, but with no natural stopping point, so the bound
	// is what it feeds on: one converter draws 70 energy/s, so the grid supports
	// income/70 of them and no more.
	// THE ADVANCED CONVERTER, WHENEVER WE CAN BUILD ONE. Nine armmakr to match
	// one armmmkr's 600-energy draw is nine footprints in the eco band and nine
	// things that die to one shell.
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
				c.investedM = -1.f;  // keep the no-decay intent under ratio scoring
				Propose(c);
			}
		}
	}

	// Spend the surplus rather than growing it further.
	if (!preT2 && (EcoSated() || aiEconomyMgr.isMetalFull))
		Propose(Simple("nano", NANO_VALUE, SideDef3("armnanotc", "cornanotc", "legnanotc"), false));
	// ON by default: attribution found the income gate, not front nanos, caused
	// the army drop. Kept, later and fewer (see FRONT_NANO_* in builder/nano.as).
	if (!preT2 && (ai.GetTunable("apex_front_nano", 1.f) > 0.f))
		Propose(Simple("frontnano", FRONT_NANO_VALUE, SideDef3("armnanotc", "cornanotc", "legnanotc"), false));

	if (!preT2) {
	Propose(Simple("gantry", GANTRY_VALUE, SideDef3("armshltx", "corgant", "leggant")));
	Propose(Simple("silo", SILO_VALUE, SideDef3("armsilo", "corsilo", "legsilo")));
	// apexearth: "Antinuke should be standard for all games where nukes are
	// allowed." Until this want existed, land maps had NO antinuke rule at all
	// -- the only chain carrying one hangs off the FLOATING radar hub.
	Propose(Simple("antinuke", ANTINUKE_VALUE, SideDef3("armamd", "corfmd", "legabm")));
	Propose(Simple("pulsar", PULSAR_VALUE, SideDef3("armanni", "cordoom", "legstarfall")));
	Propose(Simple("pinpoint", PINPOINT_VALUE, SideDef3("armtarg", "cortarg", "legtarg")));
	}

	if (gWants.length() == 0)
		return null;

	// Descending by score, first rule that accepts wins. Ranking every
	// under-budget category ahead of every at-budget one was tried and measured
	// worse: early on everything reads under target, so the partition decides
	// nothing while destabilising the order. Coverage scaling in the want's own
	// value is the lever that works instead.
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
	// constructor's job is the upgrade -- if the enqueue fails (spot taken,
	// already upgrading), it goes back to the engine's own work rather than
	// starting a Pulsar instead. Ranking decides order among optional things;
	// it does not get to displace the economy that pays for them.
	//
	// ONLY AN UPGRADE **THIS** BUILDER COULD DO BLOCKS ANYTHING: a T1 constructor
	// must not be blocked out of the whole optional class by a moho it is
	// physically unable to build.
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
		// A COVERAGE GAP IS NOT OPTIONAL SPENDING EITHER. `have` on a defence want
		// is FenceCountNear at the chosen point, so zero means bare, not thin.
		// Thickening a stretch that already has cover still waits for the
		// upgrade, which keeps this from becoming a general exemption.
		const bool gap = ((w.kind == "fence") || (w.kind == "aa")) && (w.have == 0);
		// The mexup monopoly ends at late-game income: an upgrade candidate
		// always exists, so this skip starved every adv-con want forever --
		// including the front-line T3 turrets only an adv con can build
		// (apexearth, watching a huge-economy player: "0 T3 turrets at the
		// front edge of their base"). Past the bar the RANKING decides; the
		// mexup lane in the pipeline still keeps one upgrade always running.
		if ((w.kind != "mexup") && (w.kind != "mex") && haveMexUp && !gap
			&& (aiEconomyMgr.metal.income
				< ai.GetTunable("apex_mexup_monopoly_income", 100.f)))
			continue;
		// "aa" is placed exactly like a fence -- a DEFENCE build task at a chosen
		// site. Only the budget row it is scored against differs.
		if ((w.kind == "fence") || (w.kind == "aa")) {
			// PRIORITY IS WHAT DECIDES WHETHER ANYONE IS EVER SENT.
			// CBuilderManager::MakeBuilderTask skips a candidate whose site is
			// threatened and enemy-influenced -- except at NOW, whose own comment
			// reads "Disregard safety". A front site is threatened and
			// enemy-influenced by definition, so at NORMAL these orders sit on
			// the books forever, unelectable.
			const Task::Priority prio = (ai.GetTunable("apex_front_now", 0.f) > 0.f)
					? Task::Priority::NOW : Task::Priority::NORMAL;
			// A defence request owns its patch of ground, not the whole def:
			// two towers at two places on the line are both wanted. Requests
			// refuses only a second order for THIS stretch.
			bool made = false;
			IUnitTask@ t = Requests::Take(unit, w.def, Task::BuildType::DEFENCE,
					prio, w.pos, 0.f, SQUARE_SIZE * 4, made);
			if (made) {
				++gFenceOrders;
				Builder::CloakWithWalls(unit, w.def, w.pos, prio);
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
			// Same capability hole as the mexup want one block down: a nano
			// turret reaching this want was handed 31 mex tasks in one audited
			// game, every one nulled by the guard as an orphan.
			CCircuitDef@ mexDef = SideDef3("armmex", "cormex", "legmex");
			if ((mexDef !is null) && !unit.circuitDef.CanBuild(mexDef))
				continue;
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
			// Only an asker that can BUILD the moho: cordecom clears the
			// adv-con cost bar without carrying the moho in buildOptions, and
			// this want re-elected it into the capability guard 177 times in
			// one audited game -- a hot loop spending elections on nothing.
			if ((w.def !is null) && !unit.circuitDef.CanBuild(w.def))
				continue;
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
