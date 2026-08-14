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

// T1 energy converters: 1 metal, 1,150 energy, 2,600 buildtime -- free in the
// scarce resource, paid for in the one being thrown away. The only real cost is
// builder TIME, which is why the floor below checks we can spare a builder
// first and never takes the last two.
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

// Enemy centroid this close to home means they are in the base. Widened from
// GetEnemyPos's raw reading, since that is the centroid of ALL enemies and on a
// spread-out team sits mid-map even while one enemy is standing in our base.
const float COMM_BASE_DANGER = 2200.f;
const int   COMM_HIDE_PERIOD = 30 * SECOND;
int gNextCommHide = 0;
// OFF. On a small 4v4 map the enemy team centroid can sit under COMM_BASE_DANGER
// for the whole game regardless of whether anyone is actually attacking, since
// BaseUnderAttack() at map-centroid scale reads map size rather than threat --
// this fired the commander's back-wall job on repeat instead of its opening
// build. COM_RETREAT_HEALTH (health-based retreat) is unaffected by this flag
// and still pulls a commander out of real danger.
const bool COMM_BACK_WALL_ON = false;
string armsolar("armsolar");  string corsolar("corsolar");  string legsolar("legsolar");
// Obsolete T1 economy and AA, by faction; ObsoleteReclaim only looked at
// defence towers and the opening solar, so this was previously untouched.
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
	// Enemy influence AT our own position, not distance to GetEnemyPos() (the
	// centroid of all known enemies, which in a team game rarely comes near our
	// base even during a raid) -- the same local signal the commander's flee
	// rule already trusts.
	if (ai.GetEnemyInflAt(gHomePos)
		> ai.GetTunable("apex_base_attack_infl", 0.f))
	{
		return true;
	}
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

// income - pull understates waste, since pull counts demand met from storage as
// well as from income -- a spilling base can still show almost no "spare". A
// full store is unambiguous: Economy::AiUpdateEconomy sets isEnergyFull at 88%
// of storage, and past that every joule made is a joule binned.
bool EnergyWasting()
{
	return aiEconomyMgr.isEnergyFull || (EnergySpare() >= CONVERT_MIN_SPARE);
}

// The eco lead's converter BLOCK -- a packed rectangle from Base::'s shared
// grid, not the one-every-25s trickle the generic rule below places. A
// converter eats 70 energy/s and returns 1 metal/s for 1 metal to build, so
// spare energy is worth converting at essentially no metal outlay.
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
	// The eco lead's contribution is the packed BLOCK and a faster cadence, not
	// exclusive permission to convert -- EnergyWasting() below is the gate for
	// everyone. Self-limiting: every converter raises pull by 70, so the store
	// drains and this stops on its own.
	if (!EnergyWasting())
		return null;

	// An advanced converter when the constructor asking can build one. Chosen off
	// the BUILDER's cost, not off gHaveAdvCon: only advanced constructors carry
	// armmmkr in their buildoptions, and handing a T1 constructor a task it can't
	// build is dropped silently. Two ways to earn it: the asking constructor
	// being advanced is the safe case; otherwise, once the small block is
	// established and the team holds advanced constructors, ask anyway and let
	// one pick the task up -- if nothing claims it the small block keeps
	// converting, so the downside is bounded.
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
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, want, Task::BuildType::CONVERT,
			Task::Priority::NORMAL, spot, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
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
	// constructors carry only the naval def. SmallConvDef avoids the mirror case
	// (a naval builder handed the land def) the same way.
	// Upgrade rather than keep laying T1: once the advanced converter is
	// buildable, ObsoleteReclaim is trying to clear the small ones, and this rule
	// was previously replacing them as fast as they were reclaimed.
	CCircuitDef@ want = BigConvDef(unit);
	if ((want is null) || !want.IsAvailable(ai.frame))
		@want = SmallConvDef(unit);
	if ((want is null) || !want.IsAvailable(ai.frame))
		return null;
	// No new T1 converters once the ground is worth more than they return:
	// reclaiming one and immediately rebuilding it is worse than leaving it.
	if (LandIsPrecious() && (want is SmallConvDef(unit)))
		return null;

	// The outstanding bound EcoConverters already carries, for the reason its own
	// comment gives: count sees FINISHED buildings only and Enqueue does not
	// dedup, so without this the cooldown alone re-asks forever. An unassigned
	// task also holds a slot in the shared build-task budget for 300s, which is
	// the budget mex expansion draws from.
	CCircuitDef@ smallConv = SmallConvDef(unit);
	CCircuitDef@ bigConv = BigConvDef(unit);
	const int built = ((smallConv is null) ? 0 : smallConv.count)
			+ ((bigConv is null) ? 0 : bigConv.count);
	int outstanding = gConverts - built;
	if (outstanding > CONV_STALE) {
		gConverts = built;
		outstanding = 0;
	}
	if (outstanding >= CONV_INFLIGHT)
		return null;

	AIFloat3 spot;
	if (!ConvSpot(unit, want, spot))
		return null;
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, want, Task::BuildType::CONVERT,
			Task::Priority::NORMAL, spot, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	gNextConvert = ai.frame + CONVERT_PERIOD;
	++gConverts;
	AiLog(Factory::T() + "apex: converter " + want.GetName()
		+ " spare=" + formatFloat(spare, "", 0, 0)
		+ " workers=" + aiBuilderMgr.GetWorkerCount()
		+ " asked=" + gConverts + " standing=" + want.count);
	return post;
}

}  // namespace Builder
