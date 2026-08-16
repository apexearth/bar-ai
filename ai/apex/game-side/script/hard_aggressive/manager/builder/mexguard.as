namespace Builder {

// A light turret on an undefended mex: cheap relative to the mex it protects
// and the army time a leak costs. Distinct from ContestTower, which refuses a
// T1 turret past that tier -- here the cheap turret only has to beat a scout.
//
// Must land within MEX_IN_RANGE (420) of the mex; MEX_IN_RANGE can't be named
// here since AngelScript resolves globals in declaration order and it's
// declared later in this file, so this radius is set below that value directly.
const float MEX_GUARD_RADIUS = 400.f;
// Guard count scales with how forward the mex is. FrontT is the home->enemy
// axis used elsewhere for constructor safety. Floor is 1, never 0: only
// LandIsPrecious may add a second guard on a REAR mex, never remove the one on
// a forward mex. Thresholds are set against the range of frontT our own mexes
// actually occupy (well under the 0..1 the axis defines), so all three tiers
// see traffic instead of everything landing in one bucket.
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
// How far a constructor will travel to guard one -- kept short so a builder
// isn't sent on a cross-map walk that gets it killed.
const float MEX_GUARD_REACH  = 1200.f;
// A mex with NOTHING covering it gets a longer reach, since the alternative is
// it staying bare forever. Ordinary constructors only -- the commander keeps
// the short reach, since walking it across the map is how games are lost.
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

// Geothermal (armgeo/corgeo/leggeo): a T1-con-buildable generator with an
// energy/metal ratio far above solar's, but it only exists on a fixed vent
// tile, not anywhere the ordinary layout grid can place it. GetEnergyMake
// already prices it correctly (CEconomyManager::GetEnergyMake reads the
// geo-specific "make" value for any def with IsNeedGeo()), so it slots into
// the same per-metal ranking as every other rung once HomeEnergy can find a
// vent at all -- see aiEconomyMgr.FindOpenGeoSpot's own comment for why that
// query did not exist until now.
string armgeo("armgeo"); string corgeo("corgeo"); string leggeo("leggeo");

CCircuitDef@ GeoDef()
{
	return SideDef3(armgeo, corgeo, leggeo);
}

// apexearth, watching an E-stall he traced to an early geo: "geos are a bit
// e-expensive to make. Usually you don't want to start one at less than
// 300 e/s." armgeo costs 13,000 ENERGY to build (against a mere 560 metal),
// so EnergyValuePerMetal's make/cost ratio alone -- the same ranking that
// correctly orders wind/solar/adv-solar/fusion -- looks excellent for geo at
// any income, since it only measures ongoing efficiency, not whether the
// economy can survive paying the up-front energy cost. Same shape as
// FUSION_PREFER_INCOME just above: a real number from him, not derived, kept
// as a tunable rather than hand-waved.
const float GEO_MIN_INCOME = 300.f;

// Position decides tower tier: an 85-metal Sentry suits a quiet rear extractor,
// the 190-metal Beamer (also used by statics.as) suits a forward base a raid
// arrives at in force.
//
// The commander is excluded from the advanced-constructor tier regardless of
// cost: tier is otherwise decided purely by costM >= ADV_CON_COST, and armcom
// (2700) clears that, but only armcomlvl4+ can build the advanced towers --
// asking a level-1 commander for one is a silent no-op.
bool IsAdvConDef(CCircuitUnit@ unit)
{
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return false;
	return unit.circuitDef.costM >= ADV_CON_COST;
}

// Tower tier follows economy income (T2 turret at 50 m/s, T3 at 100 m/s).
// Legion's slot uses legacluster, not legrampart: legrampart is a geothermal
// anti-nuke/jammer/radar platform buildable only on a geo vent, and its ICBM
// interceptor makes GetMaxRange() report 72,000, which would corrupt the
// front-line spacing/coverage reads that use this tower's range.
//
// All of these are buildable only by an advanced constructor; handing one to a
// T1 constructor is a silent no-op, so the ladder only applies where it can
// actually climb it.
string armtoast("armamb");   string cortoastd("cortoast");  string legramp("legacluster");
string armpulsar("armanni"); string corpulsar("cordoom");   string legpulsar("legbastion");
const float DEF_TIER_T2_INCOME = 50.f;
const float DEF_TIER_T3_INCOME = 100.f;

// Threat denied per metal -- the same measure Brain's defence want uses, so this
// ranking and that one agree on what a turret is worth.
float HeavyWorth(CCircuitDef@ def)
{
	if ((def is null) || !def.IsAvailable(ai.frame) || (def.costM <= 0.f))
		return 0.f;
	// Not a gun: TowerDenial's no-gun case returns a flat 1.0, which would read
	// as a cheap tower rather than no tower.
	if (def.GetSurfThreat() <= 0.f)
		return 0.f;
	return Brain::TowerDenial(def) / def.costM;
}

// Ranked, not thresholded to "highest tier income clears": reach does not
// increase monotonically with cost across factions, so the higher tier can be a
// shorter-range turret. Income still gates which tiers may enter the ranking
// (affordability); it no longer decides which member wins.
// Logged only on change, since GetSurfThreat (and so the winner) is a runtime
// read from the engine's weapon defs, not something we compute ourselves.
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

// The mid tier is a SET per faction, balance-picked by count so every member
// keeps appearing: the beam/MG tower, the Maw-class pop-up (armclaw/cormaw/
// legdtr -- apexearth: "really nice defenses... they look just like walls
// when not deployed... great for defending against raiders", and NOT legdtf,
// the scavenger twin nobody can build), and Legion's Hive (apexearth:
// "useful T1.5 defense which distracts units a lot").
CCircuitDef@ MidTowerDef()
{
	array<CCircuitDef@> cands;
	cands.insertLast(SideDef3(armbeamer, corhllt, legmg));
	cands.insertLast(SideDef3("armclaw", "cormaw", "legdtr"));
	if (ai.GetSideName() == "legion")
		cands.insertLast(ai.GetCircuitDef("leghive"));
	CCircuitDef@ best = null;
	for (uint i = 0; i < cands.length(); ++i) {
		CCircuitDef@ d = cands[i];
		if ((d is null) || !d.IsAvailable(ai.frame))
			continue;
		if ((best is null) || (d.count < best.count))
			@best = d;
	}
	return best;
}

// A Maw-class pop-up reads as a wall block until it fires. Scatter a few real
// wall segments (8 metal each) beside every one we order, so the enemy cannot
// tell which block shoots until it does. apexearth: "we should put some walls
// around it - the enemy will not know which are the defenses and which are
// the walls... we can be really cheeky like this."
bool IsMawClass(const CCircuitDef@ d)
{
	if (d is null)
		return false;
	const string n = d.GetName();
	return (n == "armclaw") || (n == "cormaw") || (n == "legdtr");
}

void CloakWithWalls(CCircuitUnit@ unit, CCircuitDef@ towerDef,
		const AIFloat3& in at, Task::Priority prio)
{
	if (!IsMawClass(towerDef))
		return;
	CCircuitDef@ wall = SideDef3("armdrag", "cordrag", "legdrag");
	if ((wall is null) || !wall.IsAvailable(ai.frame))
		return;
	const int n = int(ai.GetTunable("apex_maw_cloak_walls", 4.f));
	const float step = float(SQUARE_SIZE) * 5.f;
	array<float> dx = {step, -step, 0.f, 0.f, step, -step};
	array<float> dz = {0.f, 0.f, step, -step, step, -step};
	array<AIFloat3> ring;
	for (uint i = 0; i < dx.length(); ++i) {
		AIFloat3 p = at;
		p.x += dx[i];
		p.z += dz[i];
		ring.insertLast(p);
	}
	int placed = 0;
	for (uint i = 0; (i < ring.length()) && (placed < n); ++i) {
		if (!OnMap(ring[i]))
			continue;
		bool made = false;
		// Radius one square: neighbouring blocks are their own stretches, so
		// the ledger refuses a re-ask for THIS block without blocking the next.
		Requests::Take(unit, wall, Task::BuildType::DEFENCE, prio,
				ring[i], float(SQUARE_SIZE), float(SQUARE_SIZE) * 2.f, made);
		if (made)
			++placed;
	}
	if (placed > 0) {
		AiLog(Factory::T() + "apex: cloaked " + towerDef.GetName() + " with "
			+ placed + " wall block(s)");
	}
}

CCircuitDef@ MexGuardTower(CCircuitUnit@ unit, const AIFloat3& in at)
{
	CCircuitDef@ heavy = HeavyDefenceFor(unit);
	if (heavy !is null)
		return heavy;
	if (IsAdvConDef(unit))
		return SideDef3(armpb, corvipe, legapopupdef);
	if (OnMap(at) && (Military::OnBorder(at) || Military::NearFront(at))) {
		CCircuitDef@ mid = MidTowerDef();
		if ((mid !is null) && mid.IsAvailable(ai.frame))
			return mid;
	}
	return SideDef3(armllt, corllt, leglht);
}

// Distinct from MexGuardTower's answer: a Pit Bull (680m/14,000E/15,000 build)
// takes roughly a minute of undisturbed advanced-constructor work, which the
// front line rarely offers, so this defaults to the cheaper T1-path tower
// instead. apex_front_pb=1 restores the Pit Bull.
CCircuitDef@ FrontTower(CCircuitUnit@ unit, const AIFloat3& in at)
{
	// The line gets the same tiering as anything else: a Beamer is not what a
	// 100 metal/second economy should be holding ground with.
	CCircuitDef@ heavy = HeavyDefenceFor(unit);
	if (heavy !is null)
		return heavy;
	// ON by default -- apexearth: "I never see us making the scorpion style
	// defense turrets... They can still be useful for protecting us from
	// raiders and we should have some. They make the T1.5 obsolete." The
	// build-time concern stays answerable by the tunable.
	if (ai.GetTunable("apex_front_pb", 1.f) > 0.f)
		return MexGuardTower(unit, at);
	CCircuitDef@ mid = MidTowerDef();
	if ((mid !is null) && mid.IsAvailable(ai.frame))
		return mid;
	// Null rather than a light laser once past that tier -- same as ContestTower:
	// stops the work instead of redirecting it, so the constructor returns to
	// economy work rather than building a turret not worth the metal.
	if (PastT1Tier())
		return null;
	return SideDef3(armllt, corllt, leglht);
}

// Every turret tier this file can place, not just the light one: a generator
// only needs a gun that reaches it, and excluding the heavier tiers would turn
// this preference off exactly as the base grows enough to need it.
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

// The home crew's actual job: build the energy the base runs on, ranked by
// energy-per-metal so advanced solar is reached on its own merit rather than as
// a last-resort fallback nothing else owned. Bounded by demand, not a clock: we
// stop when energy is already being wasted.
IUnitTask@ HomeEnergy(CCircuitUnit@ unit)
{
	// The crew role decides who reaches this rule by default (a home constructor
	// gets here before the Brain ranks anything); apex_energy_any=0 restores the
	// old refusal for everyone outside the HOME crew.
	if ((Crew::RoleOf(unit) != Crew::HOME)
		&& (ai.GetTunable("apex_energy_any", 1.f) <= 0.f))
	{
		return null;
	}
	// No metal-bank gate: the engine already refuses what it truly can't afford,
	// and a solar pays back in seconds of income, so gating on bank state just
	// leaves the crew idle. One of the two branches below always applies, so the
	// home crew is never out of work.
	CCircuitDef@ gen = null;
	bool pickedReactor = false;
	int geoSpotId = -1;
	bool pickedGeo = false;
	// FORCED FUSION overrides the whole ranking below, including its cooldown
	// -- see the two checks where it is set. apexearth: "make us choose fusion
	// instead of advanced solar if we have ~50 metal/s or more. We shouldn't
	// make any other energy buildings while trying to make this fusion. It is
	// very expensive so we should get it built asap." Skipping the cooldown
	// is deliberate: Requests::Take already refuses a second fusion request
	// and joins the one already in flight instead, so bypassing the cooldown
	// here means "keep sending builders to the one reactor", not "start
	// another".
	bool forcedFusion = false;
	// PANIC SOLAR: apexearth 2026-08-15, watching: "If we are totally out of
	// energy and our income is less than ~500 then we should just make a
	// basic solar. Those cost 0 energy to make. They're the go-to panic
	// solar. And always reclaimable later for the metal." isEnergyStalling
	// is the existing "totally out of energy" signal (bank near-empty and
	// income can't keep up with pull -- AiUpdateEconomy in economy.as);
	// below the income floor, waiting on the per-metal ranking (which can
	// pick fusion or advanced solar, both slow to help a stall) is the wrong
	// answer, so skip it and place the cheapest, fastest fix instead.
	const bool energyPanic = aiEconomyMgr.isEnergyStalling
			&& (aiEconomyMgr.energy.income < ai.GetTunable("apex_energy_panic_income", 500.f));
	if (energyPanic) {
		@gen = SideDef3(armsolar, corsolar, legsolar);
	} else if (EnergyWasting()) {
		// apexearth 2026-08-15, after 8 hours of "no fusions" reports: this
		// branch used to route straight to a converter, meaning a capable
		// advanced con NEVER got offered fusion while EnergyWasting() was
		// true -- and EnergyWasting() (bank >=88% full, or spare energy
		// above CONVERT_MIN_SPARE) turns out to be true almost permanently
		// once the base matures, because T1 cons keep stacking armadvsol
		// (the only reactor-tier generator THEY can build, since armfus
		// requires an advanced con) to fill exactly this branch's own
		// converter want. That kept the bank topped up, which kept
		// EnergyWasting() true, which kept blocking the one building that
		// actually fixes chronic waste at scale -- confirmed in a live
		// match: fusion-gate diag showed wasting=1 on nearly every sample
		// from 9 minutes on, income climbing to 375, advsolCount to 64,
		// fusCount stuck at 0 the entire game. A capable, well-off economy
		// should still get its reactor here instead of another converter.
		CCircuitDef@ fusWaste = (Factory::HaveAnyFactory() && IsAdvConDef(unit))
				? FusionDef(unit) : null;
		if ((fusWaste !is null) && fusWaste.IsAvailable(ai.frame)
			&& (aiEconomyMgr.metal.income
				>= ai.GetTunable("apex_fusion_prefer_income", FUSION_PREFER_INCOME)))
		{
			@gen = fusWaste;
			pickedReactor = true;
		} else {
		// No cooldown between converters: the real bound is the engine's finite
		// economy task budget (CEconomyManager::MakeEconomyTasks needs
		// buildTasksCount < workers * 8, and an unassigned task holds its slot
		// 300s), which is a COUNT, not a timer -- applied via the Brain's convert
		// want as income/draw.
		//
		// armmmkr's own buildoptions (tools/unitdef.py: armaca/armack/armacv and
		// armcomlvl5+ only, never armck) mean handing it to whichever constructor
		// reached this rule is a no-op the moment that constructor is a T1 con --
		// 2026-08-14: every one of 24 armmmkr requests in a match died with
		// hadNanoframe=0 before conT2 ever left zero. IsAdvConDef is the same
		// cost-based capability proxy mexguard.as already uses for the advanced
		// tower tier, for the same reason (no CanBuild binding exists).
		@gen = IsAdvConDef(unit) ? BigConvDef(unit) : null;
		if ((gen is null) || !gen.IsAvailable(ai.frame))
			@gen = SmallConvDef(unit);
		}
	} else {
		// One unified energy-per-metal ranking across the whole ladder: per-metal
		// value rises from solar through advsol to fusion/advfusion, so this
		// climbs the ladder unaided.
		// Wind retires once a reactor stands, same as plain solar below.
		// apexearth, watching: after our first fusion, a T1 con still built a
		// wind turbine while metal-full -- not worth a builder's time once a
		// reactor covers the base; that builder is better spent on a nano,
		// assisting a factory, or anything else once this rung stops being
		// offered. Previously ranked unconditionally on the theory that a
		// windy map's per-metal value could beat a reactor's, but a builder's
		// TIME is the scarcer resource once a reactor exists, not per-metal
		// efficiency of the marginal watt.
		CCircuitDef@ wind = HaveReactor()
				? null : SideDef3(armwin, corwin, legwin);
		// Plain solar retires once a reactor stands, same as AdvSolDef already
		// does for advanced solar -- otherwise any moment the reactor rungs were
		// unavailable dropped the ladder back to a 20-energy panel.
		CCircuitDef@ sol = HaveReactor()
				? null : SideDef3(armsolar, corsolar, legsolar);
		CCircuitDef@ adv = AdvSolDef();
		// Per-asker capability, same gap as the converter/reactor rungs below:
		// the commander cannot build the advanced solar (measured 229 blocked
		// tasks in one game, each a wasted election), and only rungs the asking
		// unit can actually build may enter the ranking at all.
		if ((wind !is null) && !unit.circuitDef.CanBuild(wind))
			@wind = null;
		if ((sol !is null) && !unit.circuitDef.CanBuild(sol))
			@sol = null;
		if ((adv !is null) && !unit.circuitDef.CanBuild(adv))
			@adv = null;
		// Reactors are always ranked (never nulled while the start cooldown
		// holds); if one wins during cooldown the caller declines rather than
		// falling back to a cheaper rung, so overbuilding wind/solar stays
		// self-correcting instead of the ladder silently regressing.
		// FusionDef already gates the fusion/advanced-fusion tier on income and
		// standing count -- fetch its answer as the single reactor candidate here.
		// An earlier, separately-fetched unconditioned armafus scored highest of
		// every candidate on energy-per-metal and so always won this ranking
		// regardless of whether any constructor could build it, permanently
		// blocking the request queue; do not reintroduce a second armafus fetch.
		// Excluded before the first factory exists: a reactor is a multi-minute
		// build-power commitment the opening's single low-buildpower builder (the
		// commander) cannot spare, so it would win this ranking and starve the
		// path to the first factory. Once any factory exists, more builders exist
		// too and the reactor competes on the same per-metal merit as everything
		// else, unrestricted.
		//
		// armfus is built by armaca/armack/armacv/armcomlvl5+ only (verified with
		// tools/unitdef.py --builders), never a T1 con -- same capability gap as
		// the converter branch above, and the same fix: only offer the reactor
		// rung to a constructor that can actually build it.
		CCircuitDef@ fus = (Factory::HaveAnyFactory() && IsAdvConDef(unit))
				? FusionDef(unit) : null;
		const bool fusionAvailable = (fus !is null) && fus.IsAvailable(ai.frame);
		// PREFER: rich enough that a reactor is simply the better spend, no
		// need to wait for the per-metal ranking to notice.
		const bool preferFusion = fusionAvailable
				&& (aiEconomyMgr.metal.income
					>= ai.GetTunable("apex_fusion_prefer_income", FUSION_PREFER_INCOME));
		// IN-FLIGHT: one is already requested and not yet standing -- send
		// this builder to it instead of starting something else, so build
		// power concentrates on the one expensive building instead of
		// spreading across it plus whatever the ranking would otherwise pick.
		const bool fusionInFlight = fusionAvailable && !HaveReactor()
				&& (Requests::InFlight(fus) > 0);
		forcedFusion = preferFusion || fusionInFlight;
		if (forcedFusion) {
			@gen = fus;
			pickedReactor = true;
		} else {
			// armgeo's own buildoptions (tools/unitdef.py --builders) start at
			// armcomlvl3 -- a level-1/2 commander cannot build it. Same blanket
			// comm exclusion IsAdvConDef already uses above for the tower tier,
			// for the same reason: no level query exists from script, so this
			// stays conservative rather than offering it and relying on
			// GuardBuildCapability to silently decline (measured: exactly this
			// happened once in a 10-minute smoke test).
			const bool geoAffordable = aiEconomyMgr.energy.income
					>= ai.GetTunable("apex_geo_min_income", GEO_MIN_INCOME);
			CCircuitDef@ geo = (geoAffordable && !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
					? GeoDef() : null;
			float geoValue = -1.f;
			if ((geo !is null) && geo.IsAvailable(ai.frame)) {
				geoSpotId = aiEconomyMgr.FindOpenGeoSpot(unit, unit.GetPos(ai.frame));
				if (geoSpotId >= 0)
					geoValue = EnergyValuePerMetal(geo);
			}
			float best = -1.f;
			float v = EnergyValuePerMetal(wind);
			if (v > best) { best = v; @gen = wind; }
			v = EnergyValuePerMetal(sol);
			if (v > best) { best = v; @gen = sol; }
			v = EnergyValuePerMetal(adv);
			if (v > best) { best = v; @gen = adv; }
			v = EnergyValuePerMetal(fus);
			if (v > best) { best = v; @gen = fus; pickedReactor = true; }
			if (geoValue > best) { best = geoValue; @gen = geo; pickedReactor = false; pickedGeo = true; }
		}
	}
	if (pickedReactor && !forcedFusion && (ai.frame < gNextFusion))
		return null;   // a reactor won; wait for it rather than dropping a rung
	if ((gen is null) || !gen.IsAvailable(ai.frame))
		return null;
	// Geo has its own placement: a specific vent tile carrying a spotId, not
	// the layout grid every other rung below goes through. Take the vent
	// directly rather than falling into Base::Spot/ReactorSpot, which have no
	// notion of "this must be built exactly here".
	if (pickedGeo) {
		IUnitTask@ geoPost = aiEconomyMgr.EnqueueGeoAt(unit, geoSpotId);
		if (geoPost !is null) {
			AiLog(Factory::T() + "apex: home energy " + gen.GetName()
				+ " geo spot=" + geoSpotId
				+ " unit=" + ((unit !is null) ? int(unit.id) : -1)
				+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
				+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0));
		}
		return geoPost;
	}
	const bool isConv = EnergyWasting();
	// The grid is a preference, never a veto: Base::Spot failing just means the
	// lattice has no free cell, and a layout rule that can't find a tidy spot
	// must still place the building rather than block the economy.
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
		// Packs against the last thing we built rather than searching outward
		// from base centre: FindBuildSiteNear spirals outward from the point
		// given, so seeding it on the last placement with a tight radius chains
		// buildings edge to edge into rows instead of scattering them.
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
	// Reactors are already threat-checked inside ReactorSpot; nothing else on
	// this path was. Measured 2026-08-15: converters kept getting proposed at
	// unsafe spots (Base::Spot/CoveredSpot/pack have no safety notion at all),
	// dispatched, and aborted by AbandonUnsafeSite before a nanoframe ever
	// formed -- repeatedly, at several DIFFERENT bad spots in a row, so energy
	// kept overflowing with zero converters ever landing despite constant
	// activity. Screen here, before dispatch, instead of relying entirely on
	// the reactive abandon check: retry once at the safe home fallback, then
	// decline rather than send a builder to die on arrival.
	if (!pickedReactor && (ThreatFor(unit, spot) > CON_THREAT_VETO)) {
		const AIFloat3 safeSpot = ai.FindBuildSiteNear(gen, gHomePos, ECO_FALLBACK_RANGE);
		if (OnMap(safeSpot) && (ThreatFor(unit, safeSpot) <= CON_THREAT_VETO)) {
			spot = safeSpot;
			via = "home-safe";
			gEcoLast = spot;
			gEcoPacked = true;
		} else {
			return null;
		}
	}
	// The ladder above decides WHAT to build; whether that starts here and now or
	// joins one already requested is Requests' answer, keyed on the SITE rather
	// than the builder -- constructors scattered around a base compute distinct
	// nearby spots, so a builder-keyed check would miss the duplication.
	// Reactors stay in batches -- see fusion.as ReactorBatchOK.
	if (IsFusion(gen)) {
		AIFloat3 sectioned;
		if (!SectionSafeSpot(gen, spot, sectioned))
			return null;
		spot = sectioned;
	}
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, gen,
			isConv ? Task::BuildType::CONVERT : Task::BuildType::ENERGY,
			Task::Priority::NORMAL, spot, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;   // joined one already requested; nothing new was asked for
	if (pickedReactor)
		gNextFusion = ai.frame + FUSION_PERIOD;
	// Converters no longer wait on a clock at all; see the EnergyWasting branch
	// above for why the bound is a count instead.
	// unit=<id> ties this creation to a specific builder/constructor, and
	// inFlight/cap show the exact economy math Requests::Take used to allow
	// it -- the two pieces needed to tell "several legitimately in parallel
	// under the income-derived cap" apart from "the cap was bypassed".
	AiLog(Factory::T() + "apex: home energy " + gen.GetName()
		+ " standing=" + gen.count
		+ " unit=" + ((unit !is null) ? int(unit.id) : -1)
		+ " at=" + int(spot.x) + "," + int(spot.z)
		+ " fwd=" + formatFloat(FrontT(spot), "", 0, 2)
		+ " via=" + via
		+ " inFlight=" + Requests::InFlight(gen) + " cap=" + Requests::InFlightCap()
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
		+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0));
	return post;
}

CCircuitDef@ ContestTower(CCircuitUnit@ unit)
{
	if (IsAdvConDef(unit))
		return SideDef3(armpb, corvipe, legapopupdef);
	// Null rather than a light laser once past that tier: stops the work rather
	// than redirecting it, so the constructor falls through to whatever it would
	// have done next instead of walking home for a low-value turret.
	if (PastT1Tier())
		return null;
	return SideDef3(armllt, corllt, leglht);
}

}  // namespace Builder
