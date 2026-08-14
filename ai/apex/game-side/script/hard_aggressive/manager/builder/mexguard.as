namespace Builder {

// A light turret on an undefended mex.
//
// apexearth: "We're losing too many mexes to tiny units from the enemies because
// we aren't making an llt to defend them... it just takes that little bit of
// metal to save mexes from dying.. its very worth doing in the early game... our
// armies waste so much time chasing leaks around."
//
// The turret is 130-150 metal against a mex at 620 plus whatever the raid then
// costs in army attention, so this pays for itself on the first leak it stops.
// Distinct from ContestTower, which deliberately refuses a T1 turret once we are
// past that tier: at a mex the cheap turret is the right answer precisely because
// it only has to beat a scout.
// HOW FAR FROM THE MEX A GUARD MAY BE PLACED.
//
// apexearth, watching: "We still have a lot of mexes that don't get guarded."
// This was 260, commented "turret sits on top of the mex", and that comment was
// written for a 32-elmo LLT. MexGuardTower returns armanni/armamb/legbastion
// (64-80 elmos) once income passes 50-100 m/s, and armpb/corvipe for any
// advanced constructor -- so on a 64-elmo mex sitting on its own resource-spot
// terrain, 260 is a thin annulus, FindBuildSiteNear returns nothing, and the
// rule returns null WITHOUT SAYING SO. A guard that is never placed and a guard
// that is refused look identical from the log.
//
// 400 is the largest value that keeps the invariant below: a guard must land
// within MEX_IN_RANGE (420) of the mex or it does not cover what it was built
// for, and MEX_IN_RANGE cannot be named here because AngelScript resolves
// globals in declaration order and it is declared further down this file.
const float MEX_GUARD_RADIUS = 400.f;
// HOW MANY TURRETS A MEX WANTS IS A FUNCTION OF WHERE IT SITS.
//
// apexearth: "The closer our metal extractors are to the enemy, the more
// defenses we should be building on them. All of our mexes need to have at
// least 1 turret in range to defend it."
//
// FrontT projects a position onto the home->enemy-centroid axis: 0 at our base,
// 1 at the enemy. That is the same measure the constructor safety rules already
// use, so a forward mex here is forward by the AI's own existing definition.
//
// The floor is 1 and never 0, at any income and any distance. LandIsPrecious
// only decides whether a REAR mex also gets a second one -- it may not take the
// last turret off a mex, and it does not apply forward at all, where the ground
// being contested is the whole reason the turrets are there.
// The thresholds are set against the range WE ACTUALLY HOLD, not against the
// 0..1 the axis defines. Measured over a 20-minute 4v4, 76 guard placements: our
// own mexes span frontT -0.01 to 0.44 and stop there, because a mex past midfield
// is the enemy's. Thresholds of 0.35/0.60 put 69 of 76 in the rear tier and fired
// the forward tier zero times -- a gradient that does not engage is not a
// gradient. 0.20/0.40 splits the range we occupy into three populated tiers.
const float MEX_GUARD_MID_FRAC = 0.20f;
const float MEX_GUARD_FWD_FRAC = 0.40f;

uint MexGuardWanted(const AIFloat3& in at)
{
	const float t = FrontT(at);
	if (t >= MEX_GUARD_FWD_FRAC)
		return 4;
	if (t >= MEX_GUARD_MID_FRAC)
		return 3;
	return LandIsPrecious() ? 1 : 2;
}
// How far a constructor will travel to guard one. Measured on the first run:
// a turret was ordered on a mex 3,029 elmos away, which is the walk that gets
// constructors killed and is why this rule has to be about the mex you are
// standing next to.
const float MEX_GUARD_REACH  = 1200.f;
// A mex with NOTHING covering it is the exception to that, because the
// alternative to a long walk is the mex staying bare forever: no constructor
// may ever pass within 1200 of it. Ordinary constructors only -- the commander
// keeps the short reach, since walking it across the map is how games are lost.
const float MEX_BARE_REACH   = 2400.f;
// Radius counted when asking how thick defence around a mex already is.
const float MEX_COVER_RADIUS = 700.f;
// A turret only defends what it can SHOOT, and armllt/corllt/leglht reach 430.
// MEX_COVER_RADIUS answers "how thick is defence around here", which is the
// right question for ranking and the wrong one for "is this mex defended" -- a
// tower 700 elmos away covers nothing. Anything this rule places lands within
// MEX_GUARD_RADIUS of the mex, so a guard it builds always counts.
const float MEX_IN_RANGE     = 420.f;
// How much the walk from the builder counts against exposure. Small: it breaks
// ties between comparable mexes without letting a safe mex underfoot outrank a
// bare one on the front.
const float MEX_WALK_WEIGHT = 0.25f;
const float MEX_GUARD_HERE   = 400.f;

CCircuitDef@ MexDef()
{
	return SideDef3(armmex, cormex, legmex);
}

// WHAT A SENTRY IS AND IS NOT FOR. apexearth: "we still make too many t1
// turrets, need to make much more t1.5 turrets to protect those forward bases
// early game", alongside "in early game we should put a light laser turret near
// every mex spot".
//
// Both, and the position decides which: an 85-metal Sentry is the right answer
// for a quiet extractor behind the line, and the wrong one for a forward base,
// where a raid arrives in force and a Sentry is a speed bump. The Beamer is 190
// metal for materially more gun -- the same def statics.as reaches for when it
// wants something an attack cannot simply walk past.
// A COMMANDER IS NOT AN ADVANCED CONSTRUCTOR, WHATEVER IT COSTS. The tier here
// is decided by cost, ADV_CON_COST is 300, and armcom costs 2700 -- so every
// tower the commander was ever asked to build was a Pit Bull, which
// `unitdef.py armpb --builders` lists as buildable by armcomlvl4 and up. A
// level-1 commander cannot build one, and asking for it is a silent no-op.
//
// This is why the commander still left its mexes bare after CommanderMexGuard
// was added to fix exactly that: the rule fired and the def was unbuildable.
// apexearth: humans "walk their commanders to the front, capturing mexes on the
// way, making some llts" -- an llt is what it can actually build.
bool IsAdvConDef(CCircuitUnit@ unit)
{
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return false;
	return unit.circuitDef.costM >= ADV_CON_COST;
}

// THE TOWER TIER FOLLOWS THE ECONOMY. apexearth: "At 50 metal+ we should be
// making defenses like rattlesnakes, at 100 metal+ we should be making [Pulsar]
// T3 defenses..., the old defenses are worthless at these levels."
//
// Rattlesnake armamb 2500 / Persecutor cortoast 2500 / Eviscerator legacluster
// 2300, then Pulsar armanni 3500 / Bulwark cordoom 3000 / Bastion legbastion 4200.
//
// Legion's slot held `legrampart`, which is not a turret at all: "Geothermal
// Antinuke, Jammer, Radar and Drone Platform", buildable only on a geo vent, and
// its ICBM interceptor makes GetMaxRange() report 72,000 -- which the front-line
// want reads as its line spacing and its coverage radius. legacluster is the
// Eviscerator, 1380 range against armamb's 1380 and cortoast's 1390, and is
// already what build_chain_leg.json hangs off legalab/legavp.
//
// EVERY ONE of these is buildable only by an advanced constructor -- armack,
// armacv, armaca and the levelled commanders, per `unitdef.py <name> --builders`.
// Handing one to a T1 constructor is not a downgrade, it is a silent no-op: the
// request is dropped with no error, which is exactly how every commander tower
// this session turned out to be an unbuildable Pit Bull. So the ladder applies
// to the builders that can climb it, and everyone else keeps the cheap turret
// they can actually finish.
string armtoast("armamb");   string cortoastd("cortoast");  string legramp("legacluster");
string armpulsar("armanni"); string corpulsar("cordoom");   string legpulsar("legbastion");
const float DEF_TIER_T2_INCOME = 50.f;
const float DEF_TIER_T3_INCOME = 100.f;

// THREAT DENIED PER METAL -- the same measure the Brain's defence want scores a
// tower by, so the ladder and the ranking cannot disagree about what a turret is
// worth. Brain::TowerDenial is damage and toughness from GetSurfThreat times
// reach, and Brain::TowerReach clamps the range read, so a def carrying an
// interceptor cannot poison this the way legrampart poisoned the line's spacing.
float HeavyWorth(CCircuitDef@ def)
{
	if ((def is null) || !def.IsAvailable(ai.frame) || (def.costM <= 0.f))
		return 0.f;
	// Not a gun. legrampart -- a geothermal anti-nuke platform -- sat in this
	// candidate set until 2026-08-12, and TowerDenial's own no-gun case returns a
	// flat 1.0, which would read here as a cheap tower rather than as no tower.
	if (def.GetSurfThreat() <= 0.f)
		return 0.f;
	return Brain::TowerDenial(def) / def.costM;
}

// RANK, DO NOT THRESHOLD. apexearth: "at +50 handicap the t2 scorp defense is
// only worthwhile for a short time. you need the longer range defenses."
//
// This returned the highest tier the income cleared, so a later tier won by
// existing rather than by being better -- and two of the three factions step
// BACKWARDS in reach at that point: Cortex from a 1,390-range Persecutor at 2,500
// metal to a 950-range Doomsday at 3,000, Legion from a 1,380-range Eviscerator
// to an 1,100-range Bastion at 4,200. Handing one def to the Brain also meant its
// value function never saw the alternative and so could not correct it.
//
// The income thresholds keep their OTHER job, which is affordability: a 2,500
// metal turret is not something a 20 metal/second economy should start, and that
// is what apexearth's "at 50 metal+ ... at 100 metal+" states. They still decide
// what ENTERS the set; they no longer decide which member of it wins.
// Logged only when the answer CHANGES, so it reports the tier decision without
// adding a line per builder per tick. Which def wins is a runtime question --
// GetSurfThreat is computed by CircuitAI from the weapon defs, not by us -- so
// this is the only honest way to read the ranking back.
string gHeavyPickLast = "";

CCircuitDef@ HeavyDefenceFor(CCircuitUnit@ unit)
{
	if (!IsAdvConDef(unit))
		return null;
	const float inc = aiEconomyMgr.metal.income;
	CCircuitDef@ best = null;
	float bestWorth = 0.f;
	if (inc >= ai.GetTunable("apex_def_t2_income", DEF_TIER_T2_INCOME)) {
		CCircuitDef@ mid = SideDef3(armtoast, cortoastd, legramp);
		const float w = HeavyWorth(mid);
		if (w > bestWorth) {
			@best = mid;
			bestWorth = w;
		}
	}
	if (inc >= ai.GetTunable("apex_def_t3_income", DEF_TIER_T3_INCOME)) {
		CCircuitDef@ big = SideDef3(armpulsar, corpulsar, legpulsar);
		const float w = HeavyWorth(big);
		if (w > bestWorth) {
			@best = big;
			bestWorth = w;
		}
	}
	const string picked = (best is null) ? "none" : best.GetName();
	if (picked != gHeavyPickLast) {
		gHeavyPickLast = picked;
		AiLog(Factory::T() + "apex: heavy-def " + picked
			+ " worth=" + formatFloat(bestWorth, "", 0, 5)
			+ " mInc=" + formatFloat(inc, "", 0, 0));
	}
	return best;
}

CCircuitDef@ MexGuardTower(CCircuitUnit@ unit, const AIFloat3& in at)
{
	CCircuitDef@ heavy = HeavyDefenceFor(unit);
	if (heavy !is null)
		return heavy;
	if (IsAdvConDef(unit))
		return SideDef3(armpb, corvipe, legapopupdef);
	if (OnMap(at) && (Military::OnBorder(at) || Military::NearFront(at))) {
		CCircuitDef@ mid = SideDef3(armbeamer, corhllt, legmg);
		if ((mid !is null) && mid.IsAvailable(ai.frame))
			return mid;
	}
	return SideDef3(armllt, corllt, leglht);
}

// WHAT TO BUILD ON THE LINE ITSELF, which is not the same question as what to
// put on a mex. An advanced constructor at a mex gets a Pit Bull, and the Brain's
// front request inherited that: 20+ Pit Bulls ordered per player per game at 0.38
// to 0.70 of the way to the enemy, and ZERO ever finished. It is 680 metal,
// 14,000 energy and 15,000 build time -- roughly a minute of undisturbed work by
// one advanced constructor, standing on contested ground.
//
// The A/B arm below builds the same thing the T1 path already builds on the
// border instead. apex_front_pb=1 restores the Pit Bull.
CCircuitDef@ FrontTower(CCircuitUnit@ unit, const AIFloat3& in at)
{
	// The line gets the same tiering as anything else: a Beamer is not what a
	// 100 metal/second economy should be holding ground with.
	CCircuitDef@ heavy = HeavyDefenceFor(unit);
	if (heavy !is null)
		return heavy;
	if (ai.GetTunable("apex_front_pb", 0.f) > 0.f)
		return MexGuardTower(unit, at);
	CCircuitDef@ mid = SideDef3(armbeamer, corhllt, legmg);
	if ((mid !is null) && mid.IsAvailable(ai.frame))
		return mid;
	// NOTHING, rather than a light laser, once the economy is past that tier.
	// apexearth: "the old defenses are worthless at these levels." Returning null
	// STOPS the work instead of redirecting it -- the same thing ContestTower
	// already does for the same reason -- so a T1 constructor that cannot build
	// anything worth having goes back to the economy instead of adding another 85
	// metal turret to the pile the blob audit keeps flagging.
	if (PastT1Tier())
		return null;
	return SideDef3(armllt, corllt, leglht);
}

// ENERGY UNDER COVER. apexearth: "We should prefer to build solars and wind
// farms near sentry turrets in the early game."
//
// Every turret tier this file can place, not just the Sentry: what a generator
// needs is a gun that reaches it, and excluding the heavier tiers would switch
// the preference off exactly as the base gets big enough to need it.
const int COVER_TIERS = 5;
// Fraction of the turret's OWN weapon range, read per def so a modoption that
// retunes weapons cannot silently turn this into a fixed elmo count. The value
// is MEX_IN_RANGE's ratio (420 against the 430 armllt/corllt/leglht reach),
// which is this file's existing answer to "is that thing covered".
const float COVER_FRAC = 0.90f;

CCircuitDef@ CoverDef(int tier)
{
	if (tier == 0) return SideDef3(armllt, corllt, leglht);
	if (tier == 1) return SideDef3(armbeamer, corhllt, legmg);
	if (tier == 2) return SideDef3(armpb, corvipe, legapopupdef);
	if (tier == 3) return SideDef3(armtoast, cortoastd, legramp);
	return SideDef3(armpulsar, corpulsar, legpulsar);
}

// Nearest standing turret of this def, ignoring any sitting forward of the
// ground we are willing to keep energy on -- a guard on a contested mex is
// cover, but it is not somewhere to grow the economy.
bool NearestCover(CCircuitDef@ def, const AIFloat3& in from,
		AIFloat3& out at, float& out dist)
{
	if (def is null)
		return false;
	array<CCircuitUnit@>@ have = ai.GetOwnUnitsOfDef(def, from, MEX_GUARD_REACH);
	if (have is null)
		return false;
	bool got = false;
	float best = 0.f;
	AIFloat3 bestAt;
	for (uint i = 0; i < have.length(); ++i) {
		if (have[i] is null)
			continue;
		const AIFloat3 p = have[i].GetPos(ai.frame);
		if (!OnMap(p) || (FrontT(p) >= MEX_GUARD_MID_FRAC))
			continue;
		const float d = from.distance2D(p);
		if (!got || (d < best)) {
			best = d;
			bestAt = p;
			got = true;
		}
	}
	if (!got)
		return false;
	at = bestAt;
	dist = best;
	return true;
}

// FindBuildSiteNear spirals OUTWARD, so once the ground inside a turret's reach
// is full it answers past the radius and this declines: the turret's own range
// is what bounds how much energy gathers under it, with nothing counting or
// capping. Declining always falls through to the ordinary layout.
bool CoveredSpot(CCircuitUnit@ unit, CCircuitDef@ gen, AIFloat3& out spot)
{
	if ((gen is null) || (ai.GetTunable("apex_energy_cover", 1.f) <= 0.f))
		return false;
	const AIFloat3 me = unit.GetPos(ai.frame);
	if (!OnMap(me))
		return false;
	CCircuitDef@ best = null;
	AIFloat3 bestAt;
	float bestD = 0.f;
	for (int tier = 0; tier < COVER_TIERS; ++tier) {
		CCircuitDef@ def = CoverDef(tier);
		AIFloat3 at;
		float d = 0.f;
		if (!NearestCover(def, me, at, d))
			continue;
		if ((best is null) || (d < bestD)) {
			@best = def;
			bestAt = at;
			bestD = d;
		}
	}
	if (best is null)
		return false;
	const float cover = best.GetMaxRange()
			* ai.GetTunable("apex_energy_cover_frac", COVER_FRAC);
	if (cover <= 0.f)
		return false;
	const AIFloat3 site = ai.FindBuildSiteNear(gen, bestAt, cover);
	if (!OnMap(site) || (site.distance2D(bestAt) > cover))
		return false;
	spot = site;
	return true;
}

// The home crew's actual job: build the energy the base runs on.
//
// apexearth: "I do not think the 'home' cons are actually focusing on economy...
// the stage before fusion when we should be making advanced solars - we just
// aren't making many of those at all... so our overall economy is much further
// behind the enemies."
//
// He is right, and the reason is placement in the ladder. Advanced solar existed
// only as a LAST-RESORT fallback at the very end of AiMakeTask, behind a
// cooldown and behind every other offer. Nothing owned it. armadvsol is 350
// metal for 75 energy against armsolar's 155 for 20 -- more than twice the
// energy per metal, and it is the whole pre-fusion energy curve.
//
// Bounded by demand, not a clock: we stop when energy is already being wasted.
IUnitTask@ HomeEnergy(CCircuitUnit@ unit)
{
	// ANY BUILDER MAY MAKE ENERGY. apexearth: "Always be building energy", and
	// then "Allow others outside of home crew too...".
	//
	// The crew role decided WHO, and that made "always" false: this returned null
	// for every constructor outside the two-strong HOME crew, so the Brain's
	// energy want -- the one it proposes every single tick -- did nothing for the
	// rest of the base. Measured against the pre-Brain build at minute 14, energy
	// produced 206,124 -> 170,830 per player while waste tripled.
	//
	// The crew still decides who does it BY DEFAULT, because a home constructor
	// reaches this through its own rule before the Brain ever ranks anything.
	// What is gone is the refusal: when the ranking says energy is the best use
	// of this builder, the builder is allowed to build it.
	//
	// Off with apex_energy_any=0, which restores the crew-only behaviour.
	if ((Crew::RoleOf(unit) != Crew::HOME)
		&& (ai.GetTunable("apex_energy_any", 1.f) <= 0.f))
	{
		return null;
	}
	// NO metal-empty gate. "Don't spend when broke" is exactly backwards for the
	// one thing that ends being broke: a solar is 155 metal and pays back
	// forever, which at 13 metal/second is twelve seconds of income. Measured:
	// t0 sat pinned near zero bank for 30 minutes with home=2 constructors whose
	// only job this is, and fired it ZERO times. The engine already refuses what
	// it truly cannot afford, so the guard bought nothing and cost everything.
	//
	// apexearth's rule, verbatim: "maxEnergy ? buildConverters : buildEnergy".
	//
	// The point is that the home crew is NEVER out of work -- one branch or the
	// other always applies. My previous version declined whenever energy looked
	// momentarily plentiful, which in the early game is nearly always, so the
	// home crew sat idle and the economy fell behind: "only sinbearer seems to
	// be doing much eco".
	CCircuitDef@ gen = null;
	bool pickedReactor = false;
	if (EnergyWasting()) {
		// NO PERIOD BETWEEN CONVERTERS. apexearth: "It doesn't make sense for us to
		// have that at all. We don't need some period between creating these
		// things. That's a very bad idea."
		//
		// What the timer was standing in for is real but is not a timer: the
		// engine's economy budget is finite (CEconomyManager::MakeEconomyTasks
		// returns null unless buildTasksCount < workers * 8) and an unassigned task
		// holds its slot for 300s. The bound for that is a COUNT -- how many the
		// spill can actually feed -- which the Brain's convert want already applies
		// as income/draw. A clock only makes us slow to fix a surplus.
		// Spilling energy: turn it into metal.
		@gen = BigConvDef(unit);
		if ((gen is null) || !gen.IsAvailable(ai.frame))
			@gen = SmallConvDef(unit);
	} else {
		// PICK THE BEST ENERGY PER METAL, ACROSS THE WHOLE LADDER AT ONCE.
		//
		// This block used to decide wind against solar per metal and then rank
		// that winner against advanced solar and the reactors by RAW OUTPUT,
		// because per-metal ranking was believed unable to tier up. The defs say
		// otherwise: energy per metal RISES from solar through advanced solar to
		// fusion and advanced fusion, so one unified per-metal ranking climbs the
		// ladder unaided. Only wind is map-dependent enough to ever beat a
		// reactor, which is the whole of the special-casing that is needed.
		CCircuitDef@ wind = SideDef3(armwin, corwin, legwin);
		// PLAIN SOLAR RETIRES WHEN A REACTOR STANDS, exactly as AdvSolDef already
		// retires the advanced one. Only advanced solar was being retired, so any
		// moment the reactor rungs were unavailable dropped the ladder onto a
		// 20-energy panel. apexearth, watching live: "I see us making basic solars
		// when we have over 2000 energy per second."
		CCircuitDef@ sol = HaveReactor()
				? null : SideDef3(armsolar, corsolar, legsolar);
		CCircuitDef@ adv = AdvSolDef();
		// A reactor is 4,300-9,700 metal against a turbine's 40, and this function
		// is offered a constructor about thirty times a game-minute. Without a
		// cooldown every idle builder queues its own reactor off the same reading
		// of the same income. The cheap rungs stay uncapped -- overbuilding wind
		// is self-correcting, overbuilding fusions is the economy.
		// THE COOLDOWN BOUNDS HOW OFTEN A REACTOR IS STARTED, NOT WHICH RUNG WE
		// ARE ON. Nulling the reactor rungs for the ranking demoted the ladder to
		// its bottom step while the cooldown held -- and AdvSolDef() is already
		// null once any reactor stands, so the only candidates left were wind and
		// solar. Measured 2026-08-13 at +50 handicap: 1,787 of ~2,065 home-energy
		// placements were armwin, 1,004 of them above 5,000 energy income. Rank
		// the reactors always; if one wins while the cooldown holds, decline the
		// builder rather than handing it a turbine.
		CCircuitDef@ fus = FusionDef(unit);
		CCircuitDef@ afus = null;
		// armacsub/coracsub carry the underwater reactor and no land one, and
		// there is no naval advanced reactor to reach for.
		if (!IsNavalBuilder(unit))
			@afus = SideDef3(armafus, corafus, legafus);

		// ONE RANKING PASS. A reactor no longer waits for a bank of metal to
		// fill before it may be chosen -- apexearth: "You don't need to wait for
		// some 'bank of metal' before starting a fusion or anything like that."
		// Order matters only for pickedReactor: nothing after afus can win.
		float best = -1.f;
		float v = EnergyValuePerMetal(wind);
		if (v > best) { best = v; @gen = wind; }
		v = EnergyValuePerMetal(sol);
		if (v > best) { best = v; @gen = sol; }
		v = EnergyValuePerMetal(adv);
		if (v > best) { best = v; @gen = adv; }
		v = EnergyValuePerMetal(fus);
		if (v > best) { best = v; @gen = fus; pickedReactor = true; }
		v = EnergyValuePerMetal(afus);
		if (v > best) { best = v; @gen = afus; pickedReactor = true; }
	}
	if (pickedReactor && (ai.frame < gNextFusion))
		return null;   // a reactor won; wait for it rather than dropping a rung
	if ((gen is null) || !gen.IsAvailable(ai.frame))
		return null;
	const bool isConv = EnergyWasting();
	// The grid is a PREFERENCE, never a veto. Base::Spot failing means the
	// lattice has no free cell -- measured on Callisto, t0 hit noroom=67 and
	// placed=0 and therefore built no economy at all for the whole game, while
	// players whose grid was working (placed=13, 29) built normally. A layout
	// rule that cannot find a tidy spot must still put the building down.
	// apexearth: "we run out of room due to our terribly inefficient placement
	// of buildings."
	AIFloat3 spot;
	// A reactor is placed on exposure rather than on the layout, and never packed
	// against the last eco building: ReactorSpot leaves gEcoLast alone so the eco
	// block does not chain out to the back line behind it.
	int rear = 0;
	if (pickedReactor)
		rear = ReactorSpot(unit, gen, spot);
	string via = "eco";
	if (rear == 1)
		via = "heavy";
	else if (rear == 2)
		via = "rear";
	bool placed = (rear != 0);
	// A generator under a turret DOES become the packing anchor, where a reactor
	// deliberately does not: cover is ground we want the eco block to grow on.
	if (!placed && !isConv && !pickedReactor && CoveredSpot(unit, gen, spot)) {
		via = "cover";
		gEcoLast = spot;
		gEcoPacked = true;
		placed = true;
	}
	if (!placed) {
	if (!Base::Spot(unit, gen, Base::ECO, spot)) {
		// PACK against the last thing we built, not around home.
		//
		// The old fallback searched outward from the base centre across
		// ECO_FALLBACK_RANGE, so every building landed in whatever hole it found
		// first -- far from the previous one. That is the scatter apexearth is
		// looking at: "we build like idiots... enemy builds much more
		// efficiently with space than we do", with stock BARb laying solid
		// rectangles of forty buildings while we spread confetti.
		//
		// FindBuildSiteNear spirals OUTWARD from the point given, so seeding it
		// on the last placement with a tight radius chains buildings edge to
		// edge into rows and blocks. Falling back to home only when that fails
		// starts a fresh block instead of abandoning the build.
		if (gEcoPacked)
			spot = ai.FindBuildSiteNear(gen, gEcoLast, ECO_PACK_RANGE);
		if (!gEcoPacked || !OnMap(spot)) {
			spot = ai.FindBuildSiteNear(gen, gHomePos, ECO_FALLBACK_RANGE);
			via = "home";
		} else {
			via = "pack";
		}
		if (!OnMap(spot))
			return null;
		gEcoLast = spot;
		gEcoPacked = true;
	} else {
		gEcoLast = spot;
		gEcoPacked = true;
	}
	}
	// ONE AT A TIME. apexearth, watching live: "I am actively seeing us build 5
	// AFUS at the same time. Our builders should see one is already being built
	// and choose to assist in building that instead."
	//
	// Builder::JoinDuplicateBuild only redirects an OFFER that DefaultMakeTask
	// made; this rule ENQUEUES directly, so it bypassed that check entirely and
	// every constructor that reached it started another reactor. Ask the same
	// question here, before enqueueing: if one of these is already under way
	// within reach, join it. Checked against `spot` -- the site about to be
	// built, not the unit -- since builders scattered around the base each
	// computed a nearby-but-distinct spot and none of them were near ENOUGH TO
	// EACH OTHER to catch it when the check was keyed on their own position.
	IUnitTask@ already = Builder::JoinTaskFor(gen, unit, spot);
	if (already !is null)
		return already;
	// The join above is capped by what the economy can feed; a full cap must
	// never excuse building a SECOND copy on the same ground. Measured live:
	// once the cap was reached, ai.FindBuildSiteNear kept returning the exact
	// same tile to every further builder, because a queued-but-not-yet-started
	// task is invisible to the engine's own site search. Decline outright
	// rather than duplicate -- the ladder will try this unit again next update.
	if (Builder::SpotCollides(gen, spot))
		return null;

	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(
			isConv ? Task::BuildType::CONVERT : Task::BuildType::ENERGY,
			Task::Priority::NORMAL, gen, spot, 0.f));
	if (post is null)
		return null;
	if (pickedReactor)
		gNextFusion = ai.frame + FUSION_PERIOD;
	// Converters no longer wait on a clock at all; see the EnergyWasting branch
	// above for why the bound is a count instead.
	AiLog(Factory::T() + "apex: home energy " + gen.GetName()
		+ " standing=" + gen.count
		+ " at=" + int(spot.x) + "," + int(spot.z)
		+ " fwd=" + formatFloat(FrontT(spot), "", 0, 2)
		+ " via=" + via
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
		+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0));
	return post;
}

CCircuitDef@ ContestTower(CCircuitUnit@ unit)
{
	if (IsAdvConDef(unit))
		return SideDef3(armpb, corvipe, legapopupdef);
	// Nothing rather than a light laser once we are past its tier. The tower was
	// chosen from the CONSTRUCTOR's cost alone, so a T1 constructor kept being
	// offered one however late the game was -- apexearth, watching at 25 minutes
	// on 130 metal/second: "i still see some of our cons retreating from front
	// line to build a light laser turret, the t1 super crappy turret... at this
	// point we shouldn't be making those anymore."
	//
	// Returning null STOPS work rather than redirecting it, which is why it is
	// safe to add on its own: the constructor falls through to whatever it would
	// have done next instead of walking home for a 150-metal turret.
	if (PastT1Tier())
		return null;
	return SideDef3(armllt, corllt, leglht);
}

}  // namespace Builder
