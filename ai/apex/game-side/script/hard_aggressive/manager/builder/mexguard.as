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
const float MEX_GUARD_RADIUS = 260.f;   // turret sits on top of the mex
// Two turrets while the economy is still small, one after that. apexearth:
// "more towers around our mexes, at least in that early phase of the game".
// A lone turret trades with a raider; a pair holds against the several that
// stock actually sends. Once LandIsPrecious the ground is worth more than the
// extra turret, and the army should be the answer.
uint MexGuardWanted()
{
	return LandIsPrecious() ? 1 : 2;
}
// How far a constructor will travel to guard one. Measured on the first run:
// a turret was ordered on a mex 3,029 elmos away, which is the walk that gets
// constructors killed and is why this rule has to be about the mex you are
// standing next to.
const float MEX_GUARD_REACH  = 1200.f;
// Close enough that we are standing on it; the walk-into-fire veto is moot.
// Radius counted when asking how covered a mex already is.
const float MEX_COVER_RADIUS = 700.f;
// How much the walk from the builder counts against exposure. Small: it breaks
// ties between comparable mexes without letting a safe mex underfoot outrank a
// bare one on the front.
const float MEX_WALK_WEIGHT = 0.25f;
const float MEX_GUARD_HERE   = 400.f;

CCircuitDef@ MexDef()
{
	return SideDef3(armmex, cormex, legmex);
}

CCircuitDef@ MexGuardTower(CCircuitUnit@ unit)
{
	const string side = ai.GetSideName();
	if (unit.circuitDef.costM >= ADV_CON_COST) {
		if (side == "cortex")
			return ai.GetCircuitDef(corvipe);
		if (side == "legion")
			return ai.GetCircuitDef(legapopupdef);
		return ai.GetCircuitDef(armpb);
	}
	if (side == "cortex")
		return ai.GetCircuitDef(corllt);
	if (side == "legion")
		return ai.GetCircuitDef(leglht);
	return ai.GetCircuitDef(armllt);
}

IUnitTask@ MexGuard(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	CCircuitDef@ mex = MexDef();
	if ((mex is null) || (mex.count <= 0))
		return null;
	CCircuitDef@ tower = MexGuardTower(unit);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;

	array<CCircuitUnit@>@ mine = ai.GetOwnUnitsOfDef(mex, gHomePos, 0.f);
	if ((mine is null) || (mine.length() == 0))
		return null;

	// Nearest undefended mex to this constructor, so it guards what it is
	// standing next to rather than walking the map.
	CCircuitUnit@ pick = null;
	float best = -1.f;
	const AIFloat3 me = unit.GetPos(ai.frame);
	for (uint i = 0; i < mine.length(); ++i) {
		if (mine[i] is null)
			continue;
		const AIFloat3 at = mine[i].GetPos(ai.frame);
		if (!OnMap(at) || !AreaNeedsDefence(at, MexGuardWanted()))
			continue;
		const float d = at.distance2D(me);
		// The threat veto exists to stop a constructor WALKING into fire. If we
		// are already standing at the mex it does not apply -- and a mex that
		// reads hot is a mex near the enemy, which is exactly the one that needs
		// the turret. apexearth: "commander still just walked away from the 2
		// mexes, 1 radar, and 3 wind turbines he made near the enemy base."
		if ((d > MEX_GUARD_HERE) && (ThreatFor(unit, at) > CON_THREAT_VETO))
			continue;
		if (d > MEX_GUARD_REACH)
			continue;
		// Among the mexes this constructor can reach, guard the one most likely
		// to be attacked first, not merely the closest one to the builder. Same
		// score the border towers now use: (defences already near it + 1) x
		// distance to the enemy, lowest wins -- so cover spreads before it
		// thickens, and among equally bare mexes the exposed one wins.
		// apexearth: "if you fix that defense placement all our AI will do a lot
		// better. we can use that to understand where to place our lesser
		// defenses too."
		// Distance to the builder still breaks ties, so it does not walk the map.
		const float cover = float(Military::FenceCountNear(at, MEX_COVER_RADIUS));
		const float score = (cover + 1.f) * at.distance2D(aiEnemyMgr.GetEnemyPos())
				+ d * MEX_WALK_WEIGHT;
		if ((best < 0.f) || (score < best)) {
			best = score;
			@pick = mine[i];
		}
	}
	if (pick is null)
		return null;

	const AIFloat3 at = pick.GetPos(ai.frame);
	const AIFloat3 site = ai.FindBuildSiteNear(tower, at, MEX_GUARD_RADIUS);
	if (!OnMap(site))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, tower, site, 0.f));
	if (post is null)
		return null;
	NoteDigOrder(site);
	AiLog(Factory::T() + "apex: mex guard " + tower.GetName()
		+ " on a mex " + int(best) + " away, mexes=" + mex.count);
	return post;
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
	if (Crew::RoleOf(unit) != Crew::HOME)
		return null;
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
		if (ai.frame < gNextConv)
			return null;
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
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(
			isConv ? Task::BuildType::CONVERT : Task::BuildType::ENERGY,
			Task::Priority::NORMAL, gen, spot, 0.f));
	if (post is null)
		return null;
	if (pickedReactor)
		gNextFusion = ai.frame + FUSION_PERIOD;
	if (isConv)
		gNextConv = ai.frame + HOME_CONV_PERIOD;
	AiLog(Factory::T() + "apex: home energy " + gen.GetName()
		+ " standing=" + gen.count
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
		+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0));
	return post;
}

CCircuitDef@ ContestTower(CCircuitUnit@ unit)
{
	const string side = ai.GetSideName();
	if (unit.circuitDef.costM >= ADV_CON_COST) {
		if (side == "cortex")
			return ai.GetCircuitDef(corvipe);
		if (side == "legion")
			return ai.GetCircuitDef(legapopupdef);
		return ai.GetCircuitDef(armpb);
	}
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
	if (side == "cortex")
		return ai.GetCircuitDef(corllt);
	if (side == "legion")
		return ai.GetCircuitDef(leglht);
	return ai.GetCircuitDef(armllt);
}

}  // namespace Builder
