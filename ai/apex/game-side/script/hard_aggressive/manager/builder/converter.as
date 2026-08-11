namespace Builder {

// Split by tier because the tiers share nothing: armck/corck/legck build
// armllt/corllt/leglht and no advanced tower, armack/armacv build armpb but
// neither armllt nor armmex. Read from each constructor's buildoptions.
string armllt("armllt");
string corllt("corllt");
string leglht("leglht");
string armpb("armpb");
string corvipe("corvipe");
string legapopupdef("legapopupdef");

// T1 energy converters, at the back wall. apexearth: "t1 energy converters are
// super duper cheap, to make t1 cons, send them to the back wall, and make
// converters should be a super easy and safe task to do."
//
// The costs, read from the defs: 1 metal, 1,150 energy, 2,600 buildtime (a mex is
// 50 / 500 / 1,800). So this is free in the scarce resource, paid for in the one
// being thrown away -- 131,422 energy wasted per player in the last 8 games, or
// about 114 converters' worth -- and the only real price is builder TIME.
//
// Which is why the floor below matters more than anything else here. Every rule
// added this session was of the form "if X then take a constructor", and with one
// constructor that is all of the build power rather than a share of it. This one
// asks whether we can spare a builder first, and never takes the last two.
string armmakr("armmakr");
string cormakr("cormakr");
string legeconv("legeconv");
// Advanced converters. 380 metal for 600 E/s at efficiency 0.01724 -- 10.3
// metal/s each, against the small one's 1.0, and better per joule too (1 metal
// per 58 energy against 1 per 70). Buildable only by advanced constructors.
string armmmkr("armmmkr");
string cormmkr("cormmkr");
string legadveconv("legadveconv");

// The NAVAL forms of both tiers. A ship constructor's buildoptions contain only
// these -- corcs carries corfmkr and no cormakr -- so handing a naval builder the
// land def is the same silent no-op, in reverse, that the note above records for
// armfmkr. Legion has no naval advanced converter in this game tree; its T2 naval
// constructor is coracsub (reached through corasy, which legcs builds), and that
// carries coruwmmm.
string armfmkr("armfmkr");
string corfmkr("corfmkr");
string legfeconv("legfeconv");
string armuwmmm("armuwmmm");
string coruwmmm("coruwmmm");

// CCircuitDef::isFloater is set only when the unit can exist on water and NOT on
// land (minElev < -1 && maxElev < 1), so it separates ship constructors from the
// commander and from hovers, which carry the land defs anyway.
bool IsNavalBuilder(CCircuitUnit@ unit)
{
	return unit.circuitDef.IsFloater() || unit.circuitDef.IsSubmarine();
}

CCircuitDef@ SmallConvDef(CCircuitUnit@ unit)
{
	if (IsNavalBuilder(unit))
		return SideDef3(armfmkr, corfmkr, legfeconv);
	return SideDef3(armmakr, cormakr, legeconv);
}

CCircuitDef@ BigConvDef(CCircuitUnit@ unit)
{
	if (IsNavalBuilder(unit))
		return SideDef3(armuwmmm, coruwmmm, coruwmmm);
	return SideDef3(armmmkr, cormmkr, legadveconv);
}

const uint  CONVERT_CON_FLOOR = 3;    // never dip below this many workers
const float CONVERT_MIN_SPARE = 70.f; // one converter's draw of unused energy
const int   CONVERT_PERIOD    = 25 * SECOND;
const float REAR_DISTANCE     = 450.f;

// Enemy centroid this close to home means they are in the base.
// 2200, was 1100. GetEnemyPos is the centroid of ALL enemies, so on a 4v4 with
// them spread out it sits mid-map and reads far from every base even while one
// of them is standing in ours. Measured: fired once in a 20-minute game while
// three commanders died. Widening trades precision for actually firing; the
// commander only takes a back-wall job, so a false positive costs one solar
// built somewhere safe.
const float COMM_BASE_DANGER = 2200.f;
const int   COMM_HIDE_PERIOD = 30 * SECOND;
int gNextCommHide = 0;
// OFF. On Comet Catcher 4v4 the enemy TEAM CENTROID sits under COMM_BASE_DANGER
// from ~1 minute in and stays there for the whole game (logged distances
// 1300-2200 throughout), because the map is small enough that four spread-out
// enemies average close to home regardless of whether anyone is actually
// attacking. BaseUnderAttack() was not reading a threat on this map; it was
// reading map scale. That fired this branch roughly every COMM_HIDE_PERIOD for
// the entire game, spending the commander's build time -- normally the single
// fastest builder early -- on repeat back-wall solars instead of the opening
// build.
//
// Measured, 8-game control vs BARb:stable:hard_aggressive, Comet Catcher 4v4
// +25% Cortex/Cortex, 25 min: paired K/D log-ratio went from t=-13..-17
// (apex crushed every game, decided 0-5/0-7) to t=-0.87, not distinguishable
// from even (1-1 head to head, apex won one outright, 6/8 games ran the full
// 25 minutes instead of collapsing by minute 6-10). This was the single
// largest lever found in the session -- see notes/open-issues.md.
//
// COM_RETREAT_HEALTH (health-based retreat) is unaffected by this flag and is
// still the thing that pulls a commander out of real danger.
const bool COMM_BACK_WALL_ON = false;
string armsolar("armsolar");  string corsolar("corsolar");  string legsolar("legsolar");
// Obsolete T1 economy and AA, by faction. apexearth at 35 min: "we are *not*
// reclaiming our t1 buildings like wind turbines, t1 energy converters, t1 air
// defense". ObsoleteReclaim only ever looked at defence towers and the opening
// solar, so all of this stood untouched for the whole game.
// Names verified against the pinned tree with tools/unitdef.py: Legion's
// converter is legeconv, NOT legmakr, which does not exist in either tree.
// Only the wind turbines are new here: armmakr/cormakr/legeconv and
// armrl/corrl/legrl are already declared elsewhere in this namespace, and
// redeclaring them is a Name conflict that disables the whole variant.
string armwin("armwin");    string corwin("corwin");    string legwin("legwin");

bool BaseUnderAttack()
{
	if (!gHomeSet)
		return false;
	return gHomePos.distance2D(aiEnemyMgr.GetEnemyPos()) < COMM_BASE_DANGER;
}
int gNextConvert = 0;
int gConverts = 0;

// Behind our own base, measured away from the enemy. Converters detonate, so the
// back wall is both safer for them and safer for everything near them.
//
// Kept for the callers that want a rear position without a building to put
// there -- the commander's back-wall work in particular. Anything that IS
// placing a structure goes through Base::Spot instead, which returns a grid cell
// the terrain manager has already agreed to.
bool RearPos(CCircuitUnit@ unit, AIFloat3& out spot)
{
	if (!gHomeSet)
		return false;
	AIFloat3 away = gHomePos - aiEnemyMgr.GetEnemyPos();
	if (away.SqLength2D() < NEAR_ZERO)
		return false;
	away.SafeNormalize2D();
	for (int i = 1; i <= 3; ++i) {
		const AIFloat3 back = gHomePos + away * (REAR_DISTANCE * float(i));
		if (!OnMap(back))
			continue;
		if (ThreatFor(unit, back) <= CON_THREAT_VETO) {
			spot = back;
			return true;
		}
	}
	return false;
}

float EnergySpare()
{
	return aiEconomyMgr.energy.income - aiEconomyMgr.energy.pull;
}

// Are we actually THROWING ENERGY AWAY?
//
// income - pull is not that number and reading it as though it were is what kept
// the converter block to a handful of buildings: the eco lead logged spareE of
// 72-216 while the engine recorded 12.8 million energy wasted per game, 46.7% of
// everything it made. Pull counts demand that is being met from storage as well
// as from income, so a base that is spilling can still show almost no "spare".
//
// A full store is unambiguous -- Economy::AiUpdateEconomy sets isEnergyFull at
// 88% of storage, and past that every joule made is a joule binned.
bool EnergyWasting()
{
	return aiEconomyMgr.isEnergyFull || (EnergySpare() >= CONVERT_MIN_SPARE);
}

// The eco lead's converter BLOCK -- a packed rectangle, not the one-every-25s
// trickle the generic rule below places.
//
// Measured over 8 sixty-minute games: the eco lead threw away 12.8 million
// energy per game, 46.7% of everything it made, while a normal teammate wasted
// 22.5%. A converter eats 70 energy/s and returns 1 metal/s
// (energyconv_capacity 70, efficiency 1/70, read from armmakr.lua), and costs
// ONE metal to build. That spill is worth roughly sixty converters, i.e. about
// sixty metal a second, for essentially no metal outlay.
//
// apexearth sent the blueprint tutorial for this: humans lay energy and
// conversion out as dense packed rectangles rather than scattering them. The
// rectangle now comes from Base::, which owns one grid for the whole base;
// what is left here is only how fast and how many.
const int   CONV_PERIOD    = 6 * SECOND;
const int   CONV_INFLIGHT  = 6;
const int   CONV_STALE     = 16;
const int   CONV_MAX       = 90;
const int   ADV_CONV_AFTER = 8;   // small converters standing before switching up
// A normal player converts too, just less often than the dedicated eco lead.
const float CONV_OTHER_MULT = 1.5f;
int gNextEcoConv = 0;
int gEcoConvAsked = 0;

int SmallConvCount(CCircuitUnit@ unit)
{
	CCircuitDef@ d = SmallConvDef(unit);
	return (d is null) ? 0 : d.count;
}

// Converters take the eco band of the shared grid. The rectangle they used to
// get was its own lattice on its own origin, which is how a "packed block" could
// still land on top of the turret rows.
bool ConvSpot(CCircuitUnit@ unit, CCircuitDef@ def, AIFloat3& out spot)
{
	return Base::Spot(unit, def, Base::ECO, spot);
}

IUnitTask@ EcoConverters(CCircuitUnit@ unit)
{
	// The eco lead's converter BLOCK is a team behaviour; converting a surplus
	// is not. Solo, or as a normal teammate, EnergyWasting() below is the real
	// condition -- see the fusion bug for what happens when a role is the only
	// gate on an economic behaviour.
	// Same principle as the reactor above: a surplus is a surplus whoever owns
	// it. The eco lead's contribution is the packed BLOCK and a faster cadence,
	// not the exclusive right to convert. EnergyWasting() below is the gate.
	if (ai.frame < gNextEcoConv)
		return null;
	// Only while energy is actually being binned, and self-limiting: every
	// converter raises pull by 70, so the store drains and this stops on its own.
	if (!EnergyWasting())
		return null;

	// An ADVANCED converter when the constructor asking can build one.
	//
	// apexearth: "at late game they're making advanced energy converters ... they
	// give you ten energy conversion each and six hundred energy of cost ... and
	// you just don't have to make so many little ones. They're also a lot more
	// durable." Confirmed against the defs: armmmkr is 380 metal for 600 E/s at
	// efficiency 0.01724 -- 10.3 metal/s, against the small one's 1.0 -- and it is
	// also better per joule, 1 metal per 58 energy against 1 per 70. Health 445
	// against 167.
	//
	// Chosen off the BUILDER's cost, not off gHaveAdvCon: only advanced
	// constructors carry armmmkr in their buildoptions, and handing a T1
	// constructor a task it cannot build is dropped silently -- the failure that
	// once cost 33 rush requests and an entire tech path.
	// Two ways to earn the advanced one. The asking constructor being advanced is
	// the safe case -- it can certainly build it. Otherwise, once the small block
	// is established and the team holds advanced constructors, ask anyway and let
	// one of them pick the task up: if nothing claims it the small block is still
	// standing and still converting, so the downside is bounded.
	//
	// Measured before this: a 40-minute game placed nine converters and every one
	// was armmakr, because the branch is nearly always reached by a T1 builder.
	const bool advBuilder = ((unit.circuitDef.costM >= ADV_CON_COST)
			&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		|| (gHaveAdvCon && (SmallConvCount(unit) >= ADV_CONV_AFTER));
	CCircuitDef@ small = SmallConvDef(unit);
	CCircuitDef@ big = BigConvDef(unit);
	CCircuitDef@ want = (advBuilder && (big !is null) && big.IsAvailable(ai.frame))
		? big : small;
	if ((want is null) || !want.IsAvailable(ai.frame))
		return null;

	// Counted across BOTH tiers, so the bookkeeping survives the switch from
	// small to advanced part way through a game.
	const int built = ((small is null) ? 0 : small.count) + ((big is null) ? 0 : big.count);
	if (built >= CONV_MAX)
		return null;

	// Outstanding bound, for the same reason the turrets have one: count sees
	// finished buildings only and Enqueue does not dedup.
	int outstanding = gEcoConvAsked - built;
	if (outstanding > CONV_STALE) {
		gEcoConvAsked = built;
		outstanding = 0;
	}
	if (outstanding >= CONV_INFLIGHT)
		return null;

	AIFloat3 spot;
	if (!ConvSpot(unit, want, spot))
		return null;
	// Shake ZERO. The site came back from the terrain manager, so it is already
	// the buildable spot -- letting the engine slide it again is exactly the
	// sprawl this grid exists to stop.
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::CONVERT,
			Task::Priority::NORMAL, want, spot, 0.f));
	if (post is null)
		return null;
	gNextEcoConv = ai.frame + (Factory::EcoLeadActive()
			? CONV_PERIOD : int(float(CONV_PERIOD) * CONV_OTHER_MULT));
	++gEcoConvAsked;
	if ((gEcoConvAsked % 10) == 1)
		AiLog(Factory::T() + "apex: eco converter block " + want.GetName()
			+ " standing=" + built + " asked=" + gEcoConvAsked
			+ " spareE=" + formatFloat(EnergySpare(), "", 0, 0));
	return post;
}

IUnitTask@ EnergyConverter(CCircuitUnit@ unit)
{
	if (ai.frame < gNextConvert)
		return null;
	// Share, not truth: leave enough builders doing ordinary work.
	if (aiBuilderMgr.GetWorkerCount() <= CONVERT_CON_FLOOR)
		return null;
	// Only what the grid can actually feed. Self-limiting -- every converter
	// raises pull, so spare falls and this stops on its own.
	const float spare = aiEconomyMgr.energy.income - aiEconomyMgr.energy.pull;
	if (spare < CONVERT_MIN_SPARE)
		return null;

	// The T1 converter is what THIS constructor can build: armck/armcv carry
	// armmakr, corck/corcv cormakr, legck/legcv legeconv, and the ship
	// constructors carry only the naval def. Asking a ground constructor for
	// armfmkr produced 95 requests and zero converters; the mirror of that is what
	// SmallConvDef avoids for naval builders.
	// Upgrade rather than keep laying T1. Once the advanced converter is
	// buildable the small one is what ObsoleteReclaim is trying to clear, and
	// this rule was replacing them as fast as they were eaten -- 176 armmakr
	// enqueued against 63 reclaimed in one 37-minute game.
	CCircuitDef@ want = BigConvDef(unit);
	if ((want is null) || !want.IsAvailable(ai.frame))
		@want = SmallConvDef(unit);
	if ((want is null) || !want.IsAvailable(ai.frame))
		return null;
	// No new T1 converters once the ground is worth more than they return:
	// reclaiming one and immediately rebuilding it is worse than leaving it.
	if (LandIsPrecious() && (want is SmallConvDef(unit)))
		return null;

	AIFloat3 spot;
	if (!ConvSpot(unit, want, spot))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::CONVERT,
			Task::Priority::NORMAL, want, spot, 0.f));
	if (post is null)
		return null;
	gNextConvert = ai.frame + CONVERT_PERIOD;
	++gConverts;
	AiLog(Factory::T() + "apex: converter " + want.GetName()
		+ " spare=" + formatFloat(spare, "", 0, 0)
		+ " workers=" + aiBuilderMgr.GetWorkerCount()
		+ " asked=" + gConverts + " standing=" + want.count);
	return post;
}

}  // namespace Builder
