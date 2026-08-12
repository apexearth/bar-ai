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
// Rattlesnake armamb 2500 / Persecutor cortoast 2500 / Rampart legrampart 2600,
// then Pulsar armanni 3500 / Bulwark cordoom 3000 / Bastion legbastion 4200.
//
// EVERY ONE of these is buildable only by an advanced constructor -- armack,
// armacv, armaca and the levelled commanders, per `unitdef.py <name> --builders`.
// Handing one to a T1 constructor is not a downgrade, it is a silent no-op: the
// request is dropped with no error, which is exactly how every commander tower
// this session turned out to be an unbuildable Pit Bull. So the ladder applies
// to the builders that can climb it, and everyone else keeps the cheap turret
// they can actually finish.
string armtoast("armamb");   string cortoastd("cortoast");  string legramp("legrampart");
string armpulsar("armanni"); string corpulsar("cordoom");   string legpulsar("legbastion");
const float DEF_TIER_T2_INCOME = 50.f;
const float DEF_TIER_T3_INCOME = 100.f;

CCircuitDef@ HeavyDefenceFor(CCircuitUnit@ unit)
{
	if (!IsAdvConDef(unit))
		return null;
	const float inc = aiEconomyMgr.metal.income;
	if (inc >= ai.GetTunable("apex_def_t3_income", DEF_TIER_T3_INCOME)) {
		CCircuitDef@ big = SideDef3(armpulsar, corpulsar, legpulsar);
		if ((big !is null) && big.IsAvailable(ai.frame))
			return big;
	}
	if (inc >= ai.GetTunable("apex_def_t2_income", DEF_TIER_T2_INCOME)) {
		CCircuitDef@ mid = SideDef3(armtoast, cortoastd, legramp);
		if ((mid !is null) && mid.IsAvailable(ai.frame))
			return mid;
	}
	return null;
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
		// Pick the BIGGEST generator the economy can pay for.
		//
		// Ranking by energy-per-metal can never tier up. A wind turbine is 40
		// metal and a fusion 4,300 for 1,000 energy, so the turbine wins that
		// ratio at every income there will ever be -- the ladder has no top step,
		// it has no steps at all. GetEnergyMake() still decides wind against
		// solar, where the ratio question is real and map-dependent: it reports
		// what a def actually produces on THIS map, so a turbine is compared at
		// the map's own wind with no wind API needed.
		//
		// AffordableGen is the tiering rule, and it is economic power rather than
		// a tier check or a clock: a reactor becomes eligible exactly when income
		// can pay for it. That walks wind -> advanced solar -> fusion -> advanced
		// fusion on its own, at whatever pace the economy actually supports.
		CCircuitDef@ wind = SideDef3(armwin, corwin, legwin);
		CCircuitDef@ sol = SideDef3(armsolar, corsolar, legsolar);
		CCircuitDef@ adv = null;
		// armadvsol costs 5,000 energy to BUILD against armsolar's zero, so
		// below that bar it is paid for out of energy we do not have.
		// apexearth: "We shouldn't make advanced solar until we have ~200
		// energy per second."
		if (aiEconomyMgr.energy.income >= ADVSOL_MIN_ENERGY)
			@adv = SideDef3(armadvsol, coradvsol, legadvsol);
		// A reactor is 4,300-9,700 metal against a turbine's 40, and this function
		// is offered a constructor about thirty times a game-minute. Without a
		// cooldown every idle builder queues its own reactor off the same reading
		// of the same income. The cheap rungs stay uncapped -- overbuilding wind
		// is self-correcting, overbuilding fusions is the economy.
		CCircuitDef@ fus = null;
		CCircuitDef@ afus = null;
		if (ai.frame >= gNextFusion) {
			@fus = FusionDef(unit);
			// armacsub/coracsub carry the underwater reactor and no land one, and
			// there is no naval advanced reactor to reach for.
			if (!IsNavalBuilder(unit))
				@afus = SideDef3(armafus, corafus, legafus);
		}

		// WIND vs SOLAR IS A PER-METAL QUESTION, AND RAW OUTPUT ANSWERS IT WRONG.
		//
		// The ladder below ranks by raw output so that it can TIER UP -- ranking
		// by energy-per-metal would pin it on wind turbines forever, since a
		// 40-metal turbine beats a 4,300-metal fusion on that ratio at every
		// income there will ever be. But applying raw output to the wind/solar
		// pair specifically decides it backwards: armsolar makes 20 against a
		// turbine's output of the MAP'S WIND, and almost no map has wind above
		// 20, so solar wins essentially everywhere -- while costing 155 metal
		// against the turbine's 40.
		//
		// Per metal on a 12-wind map: wind 12/40 = 0.300, solar 20/155 = 0.129.
		// Break-even is around 5.2 wind. apexearth: "this map has tons of wind,
		// we should never make any solars on a map like this one... generally if
		// average wind is greater than ~7.5 then wind is better. and this map has
		// 12 wind MINIMUM."
		//
		// So decide the pair on cost-effectiveness, then hand the winner to the
		// raw-output ladder, which keeps its ability to tier up to reactors.
		CCircuitDef@ t1 = null;
		float t1Make = -1.f;
		if (ai.GetTunable("apex_wind_per_metal", 1.f) > 0.f) {
			float bestPerM = -1.f;
			if (AffordableGen(wind) && (wind.costM > 0.f)) {
				const float e = aiEconomyMgr.GetEnergyMake(wind);
				bestPerM = e / wind.costM; @t1 = wind; t1Make = e;
			}
			if (AffordableGen(sol) && (sol.costM > 0.f)) {
				const float e = aiEconomyMgr.GetEnergyMake(sol);
				if ((e / sol.costM) > bestPerM) { bestPerM = e / sol.costM; @t1 = sol; t1Make = e; }
			}
		} else {
			if (AffordableGen(wind)) {
				const float e = aiEconomyMgr.GetEnergyMake(wind);
				if (e > t1Make) { t1Make = e; @t1 = wind; }
			}
			if (AffordableGen(sol)) {
				const float e = aiEconomyMgr.GetEnergyMake(sol);
				if (e > t1Make) { t1Make = e; @t1 = sol; }
			}
		}

		float best = -1.f;
		if (t1 !is null) {
			best = t1Make; @gen = t1;
		}
		if (AffordableGen(adv)) {
			const float e = aiEconomyMgr.GetEnergyMake(adv);
			if (e > best) { best = e; @gen = adv; }
		}
		if (AffordableGen(fus)) {
			const float e = aiEconomyMgr.GetEnergyMake(fus);
			if (e > best) { best = e; @gen = fus; pickedReactor = true; }
		}
		if (AffordableGen(afus)) {
			const float e = aiEconomyMgr.GetEnergyMake(afus);
			if (e > best) { best = e; @gen = afus; pickedReactor = true; }
		}
	}
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
		if (!gEcoPacked || !OnMap(spot))
			spot = ai.FindBuildSiteNear(gen, gHomePos, ECO_FALLBACK_RANGE);
		if (!OnMap(spot))
			return null;
		gEcoLast = spot;
		gEcoPacked = true;
	} else {
		gEcoLast = spot;
		gEcoPacked = true;
	}
	// ONE AT A TIME. apexearth, watching live: "I am actively seeing us build 5
	// AFUS at the same time. Our builders should see one is already being built
	// and choose to assist in building that instead."
	//
	// Builder::JoinDuplicateBuild only redirects an OFFER that DefaultMakeTask
	// made; this rule ENQUEUES directly, so it bypassed that check entirely and
	// every constructor that reached it started another reactor. Ask the same
	// question here, before enqueueing: if one of these is already under way
	// within reach, join it.
	IUnitTask@ already = Builder::JoinTaskFor(gen, unit);
	if (already !is null)
		return already;

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
