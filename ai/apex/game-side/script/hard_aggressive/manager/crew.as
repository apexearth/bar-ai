namespace Crew {

// Constructors with a standing job, instead of one ladder every constructor
// walks from the top. A shared ladder makes priority global, so a new rule
// anywhere above DefaultMakeTask competes with mex upgrades at the bottom of
// it; roles make that competition local, since a defence rule can only ever
// compete with other defence work. The commander already works this way --
// taking mex spots until none is left, then falling through -- this
// generalises it to a crew.

enum Role { ECO = 0, MEX = 1, FRONT = 2, HOME = 3, ENERGY = 4, METAL = 5 };

// DEDICATED ROLES (apexearth 2026-08-21: "if a constructor has a role of
// 'energy' then the only thing they build are energy related items... We
// should only assign roles if we have enough cons"). Dedication is a floor,
// never a fence: the role restricts what ITS HOLDER does -- ordinary cons
// still build energy and metal freely -- so the past exclusivity failure
// (a capability gated on a role nobody held) cannot recur. Slots are a
// ratio of the fleet, not a step: one ENERGY and one METAL dedicate per
// DEDICATE_PER enlisted T1 cons. Advanced cons dedicate in share.as terms
// separately (the second adv con leans energy via the fusion chain).
const int DEDICATE_PER = 3;

// Advanced constructors dedicate on their own ratio (apexearth: "If we
// [have] 2 [T2] cons, we could assign 1 to dedicate to energy") -- and only
// to ENERGY: the adv-con-on-metal problem is the one he reported ("4 T2
// cons all upgrading mexes"), so their metal work stays with the shared
// wants.
array<bool> gAdv;   // parallel to gId: enlisted as an advanced con

int TierCount(bool adv)
{
	int n = 0;
	for (uint i = 0; i < gAdv.length(); ++i) {
		if (gAdv[i] == adv)
			++n;
	}
	return n;
}

int TierRoleCount(int role, bool adv)
{
	int n = 0;
	for (uint i = 0; i < gRole.length(); ++i) {
		if ((gRole[i] == role) && (gAdv[i] == adv))
			++n;
	}
	return n;
}

int DedicatedSlots()
{
	const int per = int(ai.GetTunable("apex_dedicate_per", TUNE_DEDICATE_PER));
	if (per <= 0)
		return 0;
	return TierCount(false) / per;
}

int AdvDedicatedSlots()
{
	const int per = int(ai.GetTunable("apex_dedicate_per_adv", TUNE_DEDICATE_PER_ADV));
	if (per <= 0)
		return 0;
	return TierCount(true) / per;
}

// Deaths shrink the fleet and Discharge shrinks the list, so the slot count
// falls on its own -- but the HOLDERS outlive their slots without this.
// Newest-first demotion keeps the longest-standing dedication stable.
void Rebalance()
{
	const int t1Slots = DedicatedSlots();
	const int advSlots = AdvDedicatedSlots();
	for (int r = int(ENERGY); r <= int(METAL); ++r) {
		for (int i = int(gRole.length()) - 1; i >= 0; --i) {
			const bool adv = gAdv[i];
			const int slots = adv ? advSlots : t1Slots;
			if ((gRole[i] == r) && (TierRoleCount(r, adv) > slots))
				gRole[i] = ECO;
		}
	}
}

// Constructors that NEVER leave the base. ECO is a catch-all default, not a
// job -- an ECO constructor still walks the whole ladder and can be sent
// anywhere; HOME is the role that guarantees some are always working economy.
const int   HOME_CREW   = 2;
const float HOME_RADIUS = 1600.f;

// How many consecutive dry checks before a mex constructor gives up the job.
//
// Not the first miss: spots are taken and lost constantly, and retiring on one
// empty look would drain the crew in the first contested minute. This asks for a
// run of them.
const int DRY_LIMIT = 6;

// Front constructors are bounded by DEMAND, never by a clock: a timer would
// refuse to reinforce a section being broken through just because something
// was built there recently. What should stop it -- existing cover, stacking,
// affordability -- is checked at the point of placement instead.
const float FRONT_SPACING = 320.f;   // don't stack towers on one spot
// Share of its own home-distance a retiring mex constructor must be within of
// the front to stay there. 1.0 reproduces the old midpoint test.
const float FRONT_CREW_BIAS = 0.7f;
array<AIFloat3> gFrontPlaced;

// How many constructors hold the mex job at once. Not a derived number --
// raising it was tried and measured worse (starves every other job without
// buying more expansion), so crew size is not the lever for the mex deficit.
const int MEX_CREW = 3;

// Roles are held per UNIT, keyed on CCircuitUnit::id. Linear scan: a crew is
// tens of units and this runs once per task decision.
array<int> gId;
array<int> gRole;
array<int> gDry;    // consecutive checks a mex member found no open spot

// What the crew is actually worth, so this can be judged rather than assumed:
// mexes it creates, and death rate against ordinary constructors.
int gMexBuilt = 0;    // mex tasks the crew enqueued
int gDiedMex = 0;     // crew members lost while holding the mex job
int gDiedFront = 0;
int gDiedEco = 0;

// What a constructor was DOING when it died, tallied by job and by whether it
// had walked forward of the front line -- role alone can't answer that, since
// "walking off to die" is a claim about the task, not the label.
array<string> gDeathKind;
array<int> gDeathCount;

void TallyDeath(CCircuitUnit@ unit)
{
	string what = "idle";
	IUnitTask@ t = unit.task;
	if (t !is null) {
		const string k = Builder::SiteBuildName(t);
		what = (k != "") ? k : "nonbuild";
	}
	const AIFloat3 at = unit.GetPos(ai.frame);
	what += Builder::PastFront(at) ? "@forward" : "@home";
	for (uint i = 0; i < gDeathKind.length(); ++i) {
		if (gDeathKind[i] == what) {
			++gDeathCount[i];
			return;
		}
	}
	gDeathKind.insertLast(what);
	gDeathCount.insertLast(1);
}

string DeathReport()
{
	string s = "";
	for (uint i = 0; i < gDeathKind.length(); ++i)
		s += " " + gDeathKind[i] + "=" + gDeathCount[i];
	return s;
}

int Slot(int id)
{
	for (uint i = 0; i < gId.length(); ++i) {
		if (gId[i] == id)
			return int(i);
	}
	return -1;
}

int CountOf(int role)
{
	int n = 0;
	for (uint i = 0; i < gRole.length(); ++i) {
		if (gRole[i] == role)
			++n;
	}
	return n;
}

int RoleOf(CCircuitUnit@ unit)
{
	if (unit is null)
		return ECO;
	const int s = Slot(int(unit.id));
	return (s < 0) ? ECO : gRole[s];
}

// A constructor appeared. The mex crew is filled first, because expansion is
// what matters earliest; everything after it works the ordinary ladder.
//
// A unit's role never changes once set. A role that can be reassigned under a
// unit is the same priority ladder again one level up, and it would undo the
// only property worth having here: that a crew member cannot be tempted away.
void Enlist(CCircuitUnit@ unit)
{
	if ((unit is null) || (Slot(int(unit.id)) >= 0))
		return;
	// Assist bots arrive as ordinary UseAs::BUILDER units, so without this they
	// take mex-crew places they will never work -- Assist::Work runs ahead of
	// MexWork and always claims them first, leaving the slot occupied and the
	// crew short.
	if (Assist::IsAssistBot(unit))
		return;
	// Home first -- the economy is the thing that must never stop.
	int role = ECO;
	if (CountOf(HOME) < HOME_CREW)
		role = HOME;
	else if (!gMexPhaseOver && (CountOf(MEX) < MEX_CREW))
		role = MEX;
	else {
		// Dedicated slots fill after the standing crews, energy first
		// (apexearth: "we simply expand our energy slowly, always").
		// Advanced cons dedicate on their own ratio, ENERGY only.
		const bool adv = Builder::IsAdvConDef(unit);
		if (adv) {
			if (TierRoleCount(int(ENERGY), true) < AdvDedicatedSlots())
				role = ENERGY;
		} else {
			const int slots = DedicatedSlots();
			if (TierRoleCount(int(ENERGY), false) < slots)
				role = ENERGY;
			else if (TierRoleCount(int(METAL), false) < slots)
				role = METAL;
		}
	}
	gId.insertLast(int(unit.id));
	gRole.insertLast(role);
	gDry.insertLast(0);
	gAdv.insertLast(Builder::IsAdvConDef(unit));
	if (role == MEX)
		AiLog(Factory::T() + "apex: crew " + unit.circuitDef.GetName()
			+ " -> mex (" + CountOf(MEX) + "/" + MEX_CREW + ")");
}

// Losing one frees its place, so the next constructor built takes over the job.
void Discharge(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const int s = Slot(int(unit.id));
	if (s < 0)
		return;
	if (gRole[s] == MEX) ++gDiedMex;
	else if (gRole[s] == FRONT) ++gDiedFront;
	else ++gDiedEco;
	TallyDeath(unit);
	gId.removeAt(uint(s));
	gRole.removeAt(uint(s));
	gDry.removeAt(uint(s));
	gAdv.removeAt(uint(s));
	// The fleet just shrank: holders beyond the new slot counts step down.
	Rebalance();
}

// A mex constructor whose job is finished picks its next one by where it is
// STANDING, since the crew ends up spread across the map: the one that took
// forward spots is already at the front and should stay, the one that took
// spots behind base is already home. Pooling them would have them walk past
// each other.
void Retire(CCircuitUnit@ unit, int slot)
{
	const AIFloat3 at = unit.GetPos(ai.frame);
	int role = ECO;
	AIFloat3 line;
	// A plain 50/50 split by distance bounds nothing -- on a wide front half
	// the retiring mex crew stays out there. Below 1.0 a constructor must be
	// CLEARLY forward to stay; at 1.0 this is the 50/50 test.
	if (Builder::gHomeSet && Front::FrontNear(at, line)
			&& (at.distance2D(line)
				< at.distance2D(Builder::gHomePos)
					* ai.GetTunable("apex_front_crew_bias", TUNE_FRONT_CREW_BIAS)))
	{
		role = FRONT;
	}
	gRole[slot] = role;
	gDry[slot] = 0;
	gMexPhaseOver = true;
	AiLog(Factory::T() + "apex: crew " + unit.circuitDef.GetName()
		+ " mex job done -> " + ((role == FRONT) ? "front" : "eco"));
}

// The mex crew's entire job.
//
// Returns null when this constructor is not on the crew, or when no open spot
// remains -- which is how the crew joins the economy without being reassigned.
// It simply stops matching here and falls through to the ordinary ladder from
// then on, and picks the job back up by itself if a spot is lost and reopens.
IUnitTask@ MexWork(CCircuitUnit@ unit)
{
	const int s = (unit is null) ? -1 : Slot(int(unit.id));
	if ((s < 0) || (gRole[s] != MEX))
		return null;
	// Stood down at T2, or out of spots -- retire on the member's next request
	// for work, which is the only place a unit handle exists to read its position
	// from. Retire picks front-or-economy by where it is standing.
	if (gMexPhaseOver) {
		Retire(unit, s);
		return null;
	}
	const int spot = aiEconomyMgr.FindOpenMexSpot(unit, unit.GetPos(ai.frame));
	if (spot < 0) {
		if (++gDry[s] >= DRY_LIMIT)
			Retire(unit, s);
		return null;
	}
	// Dispatching above the ordinary ladder would skip the threat veto the
	// normal mex path runs. A crew is a standing job, not a licence to
	// ignore the map.
	const AIFloat3 where = aiEconomyMgr.GetMexSpotPos(spot);
	if (OnMap(where)) {
		float heat = Builder::ThreatFor(unit, where);
		heat = Builder::MexHeat(where, heat);
		if (heat > Builder::CON_THREAT_VETO)
			return null;
	}
	gDry[s] = 0;
	IUnitTask@ dig = aiEconomyMgr.EnqueueMexAt(unit, spot);
	if (dig !is null)
		++gMexBuilt;
	return dig;
}

// The front crew's whole job: put defence on the line, wherever the line is.
//
// Bounded by demand, not by a clock -- see FRONT_SPACING. The three things that
// legitimately stop it are that we cannot pay for the tower, that this stretch
// already has cover, and that we would be stacking towers on one spot.
// How many of ours stand within `r` of `p`.
int CountNear(CCircuitDef@ d, const AIFloat3& in p, float r)
{
	if ((d is null) || (d.count <= 0))
		return 0;
	array<CCircuitUnit@>@ have = ai.GetOwnUnitsOfDef(d, p, r);
	return (have is null) ? 0 : int(have.length());
}

string armjamt("armjamt"); string corjamt("corjamt"); string legjam("legjam");

CCircuitDef@ JammerDef()
{
	return SideDef3(armjamt, corjamt, legjam);
}

// What this stretch of the line is missing, in the order it is worth having.
// A turret fights, so it comes first. A construction turret behind it repairs
// everything in its radius, the cheapest way to keep a line standing. A
// jammer hides the lot from radar. Jammers are also in build_chain.json, hung
// off armanni -- a hub only fires when its exact parent FINISHES, which is
// why they can arrive late or not at all from that path.
const float FRONT_SUPPORT_R = 420.f;

CCircuitDef@ FrontWant(CCircuitUnit@ unit, const AIFloat3& in where)
{
	CCircuitDef@ tower = Builder::ContestTower(unit);
	if ((tower !is null) && tower.IsAvailable(ai.frame)
			&& (CountNear(tower, where, FRONT_SUPPORT_R) < 1))
		return tower;

	CCircuitDef@ nano = Builder::NanoDef();
	if ((nano !is null) && nano.IsAvailable(ai.frame)
			&& (CountNear(nano, where, FRONT_SUPPORT_R) < 1))
		return nano;

	CCircuitDef@ jam = JammerDef();
	if ((jam !is null) && jam.IsAvailable(ai.frame)
			&& (CountNear(jam, where, FRONT_SUPPORT_R) < 1))
		return jam;

	return tower;   // thicken the line where it already has support
}

// A front line is a LATE-GAME structure: scattered cheap turrets are defeated
// in detail because each fights alone, while a T3 wall works because the
// pieces cover each other and outrange the approach. Spreading lesser defence
// along a line is strictly worse than either massing it or not buying it.
// Early defence is MexGuard's job instead: cheap turrets on the mexes that
// are actually being raided.
bool FrontLineWorthIt()
{
	return Factory::gHaveT3 || (aiEconomyMgr.energy.income >= 3000.f);
}

IUnitTask@ FrontWork(CCircuitUnit@ unit)
{
	if (RoleOf(unit) != FRONT)
		return null;
	if (!FrontLineWorthIt())
		return null;
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	AIFloat3 line;
	if (!Front::FrontNear(unit.GetPos(ai.frame), line))
		return null;
	// Stand off from the line toward home, so what we build covers the approach
	// rather than being placed in the middle of the enemy's half.
	AIFloat3 spot;
	if (!Builder::StandoffPos(unit, line, spot))
		return null;

	// What this stretch is missing -- turret, then a construction turret to keep
	// it repaired, then a jammer. Only the turret is subject to the "already
	// covered" test; support is exactly what we want where cover exists.
	CCircuitDef@ tower = FrontWant(unit, spot);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;
	const bool isTurret = (tower is Builder::ContestTower(unit));
	if (isTurret) {
		for (uint i = 0; i < gFrontPlaced.length(); ++i) {
			if (gFrontPlaced[i].distance2D(spot) < FRONT_SPACING)
				return null;
		}
		if (!Builder::AreaNeedsDefence(spot))
			return null;
	}

	const AIFloat3 site = ai.FindBuildSiteNear(tower, spot, FRONT_SUPPORT_R);
	if (!OnMap(site))
		return null;
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, tower,
			isTurret ? Task::BuildType::DEFENCE : Task::BuildType::NANO,
			Task::Priority::NORMAL, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	if (isTurret)
		gFrontPlaced.insertLast(spot);
	AiLog(Factory::T() + "apex: crew front " + unit.circuitDef.GetName()
		+ " -> " + tower.GetName() + " posts=" + gFrontPlaced.length());
	return post;
}

// Fill a vacancy from the economy pool. Enlist only ever sees NEW
// constructors, so a crew wiped out would otherwise stay empty until the
// factory makes another one. This isn't the role-churn Enlist warns against
// -- that's about a unit being tempted away from its job; this runs the same
// direction the crew already moves when spots run out, just backwards.
bool gMexPhaseOver = false;

void FillVacancies()
{
	// Once the map's spots are taken, stop refilling the crew. Without this the
	// vacancy filler and Retire fight each other: promote an economy constructor
	// to mex, it finds nothing for DRY_LIMIT checks, retires, gets promoted
	// again. Spots that reopen later are still taken -- by the ordinary ladder,
	// which is where mex expansion lives anyway.
	// Home vacancies are filled first and are never given up.
	for (uint i = 0; (i < gRole.length()) && (CountOf(HOME) < HOME_CREW); ++i) {
		if (gRole[i] != ECO)
			continue;
		gRole[i] = HOME;
	}
	if (gMexPhaseOver)
		return;
	for (uint i = 0; (i < gRole.length()) && (CountOf(MEX) < MEX_CREW); ++i) {
		if (gRole[i] != ECO)
			continue;
		gRole[i] = MEX;
		AiLog(Factory::T() + "apex: crew vacancy filled -> mex ("
			+ CountOf(MEX) + "/" + MEX_CREW + ")");
	}
}

int gNextLog = 0;

// The crew is a T1-phase institution. Members are not deleted, they RETIRE
// the same way as when spots run out -- by where they are standing -- so the
// ones already forward become front constructors instead of walking home.
void DissolveAtT2()
{
	if (gMexPhaseOver || !Factory::gHaveT2)
		return;
	gMexPhaseOver = true;
	AiLog(Factory::T() + "apex: crew stood down at T2, mexes=" + gMexBuilt);
}

void Update()
{
	DissolveAtT2();
	FillVacancies();
	if (ai.frame < gNextLog)
		return;
	gNextLog = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: crew home=" + CountOf(HOME)
		+ " mex=" + CountOf(MEX)
		+ " front=" + CountOf(FRONT) + " eco=" + CountOf(ECO)
		+ " tracked=" + gId.length() + " posts=" + gFrontPlaced.length()
		+ " mexesBuilt=" + gMexBuilt
		+ " died mex/front/eco=" + gDiedMex + "/" + gDiedFront + "/" + gDiedEco);
	if (gDeathKind.length() > 0)
		AiLog(Factory::T() + "apex: con deaths by job" + DeathReport());
}

// Is this constructor barred from working at `where`? Only the home crew is.
bool TooFarForHome(CCircuitUnit@ unit, const AIFloat3& in where)
{
	if ((unit is null) || (RoleOf(unit) != HOME) || !Builder::gHomeSet)
		return false;
	return where.distance2D(Builder::gHomePos) > HOME_RADIUS;
}

}  // namespace Crew
