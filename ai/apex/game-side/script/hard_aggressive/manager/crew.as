namespace Crew {

// Constructors with a standing job, instead of one ladder every constructor
// walks from the top.
//
// apexearth: "We typically have constructors built for certain purposes. I will
// build some, and those constructors will only work on the economy. I will then
// build some more where their only job is to capture all the mexes. and then
// they go to economy after all the mexes are gotten."
//
// The argument for this shape is structural, not a tuning preference. The worst
// regression recorded here -- twelve changes, metal production down 4.3x -- came
// from every new rule running ahead of DefaultMakeTask in ONE shared ladder,
// with mex upgrades at the bottom of it. Every rule was individually reasonable.
// Roles turn that global priority question into a local one: a defence rule can
// only ever compete with other defence work.
//
// The commander is already a crew of one -- it takes mex spots until none is
// left, then falls through to everything else. This generalises that.

enum Role { ECO = 0, MEX = 1, FRONT = 2, HOME = 3 };

// Constructors that NEVER leave the base.
//
// apexearth, watching: "the enemy usually has some cons in their base making
// economy, sometimes we don't have any, like all our cons go out to do other
// things... some should ALWAYS be doing economy at home."
//
// ECO was a catch-all default, not a job -- an ECO constructor still walked the
// whole ladder and could be sent anywhere. HOME is the role his original
// description actually asked for: "I will build some, and those constructors
// will only work on the economy."
const int   HOME_CREW   = 2;
const float HOME_RADIUS = 1600.f;

// How many consecutive dry checks before a mex constructor gives up the job.
//
// Not the first miss: spots are taken and lost constantly, and retiring on one
// empty look would drain the crew in the first contested minute. This asks for a
// run of them.
const int DRY_LIMIT = 6;

// Front constructors are bounded by DEMAND, never by a clock.
//
// apexearth: "no rate limit based on time", and USER-FEEDBACK.md: "Do not cap
// front-line defence -- if theres a frontline we should build [there]." A timer
// stops the crew for reasons that have nothing to do with the line: it would
// refuse to reinforce a section being broken through simply because it built
// something twenty seconds ago. What SHOULD stop it is that the spot already has
// cover, that the towers would stack, or that we cannot pay -- all of which are
// checked at the point of placement instead.
const float FRONT_SPACING = 320.f;   // don't stack towers on one spot
array<AIFloat3> gFrontPlaced;

// How many constructors hold the mex job at once.
//
// Measured 2026-08-08, 6-game 8v8: we make 5 mex upgrades to stock's 9 while
// holding 22 peak constructors to its 62. Three is a starting point, not a
// derived number -- it is the first thing to sweep once this is measurable.
// Raised 3 -> 5 on the survey, 2026-08-08. Across 16 games at four sizes we
// produce 53-73% of stock's metal and make 1-4 mex upgrades against its 4-7,
// and every other deficit is proportional to that: metal BUILT 40-72%,
// constructors held a quarter to a half. The constructor ratios are NOT the
// cause -- apex already asks for more constructors than stock (armck 0.45 vs
// 0.35, coracv 0.45 vs 0.01) -- so the pie is small rather than badly sliced,
// and expansion is the upstream end of that loop.
// TRIED 5, MEASURED WORSE, reverted 2026-08-08. Same map/size/factions/seeds as
// the survey arm: metal produced 30,491 -> 25,822, metal built 20,136 -> 16,230
// (40% -> 28% of stock's), mex upgrades 1 -> 0, T3 spend 615 -> 0. Five of about
// ten constructors on mex duty starves everything else and does not even buy
// expansion. The metal deficit is real but the crew size is not the lever.
const int MEX_CREW = 3;

// Roles are held per UNIT, keyed on CCircuitUnit::id. Linear scan: a crew is
// tens of units and this runs once per task decision.
array<int> gId;
array<int> gRole;
array<int> gDry;    // consecutive checks a mex member found no open spot

// What the crew is actually worth, so this can be judged rather than assumed.
// apexearth: "you can gauge it based on how many mexes the mex crew creates,
// how often mex crew guys die vs normal cons".
int gMexBuilt = 0;    // mex tasks the crew enqueued
int gDiedMex = 0;     // crew members lost while holding the mex job
int gDiedFront = 0;
int gDiedEco = 0;

// What a constructor was DOING when it died, tallied by job and by whether it
// had walked forward of the front line. apexearth: "can you tell what cons are
// usually doing when they die?" -- role alone cannot answer that, and "walking
// off to die" is a claim about the task, not the label.
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
	gId.insertLast(int(unit.id));
	gRole.insertLast(role);
	gDry.insertLast(0);
	if (role == MEX)
		AiLog(Factory::T() + "apex: crew " + unit.circuitDef.GetName()
			+ " -> mex (" + CountOf(MEX) + "/" + MEX_CREW + ")");
}

// Losing one frees its place, so the next constructor built takes over the job.
// apexearth: "And if they die, I just make more."
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
}

// A mex constructor whose job is finished picks its next one by where it is
// STANDING.
//
// apexearth: "ok all mexes i should get are gotten so if im closer to frontline
// i become a frontline con". That is the right test precisely because the mex
// crew ends up spread across the map -- the one that took the forward spots is
// already at the front and should stay there, and the one that took the spots
// behind the base is already home. Sending them all to one pool would have them
// walk past each other.
void Retire(CCircuitUnit@ unit, int slot)
{
	const AIFloat3 at = unit.GetPos(ai.frame);
	int role = ECO;
	AIFloat3 line;
	if (Builder::gHomeSet && Front::FrontNear(at, line)
			&& (at.distance2D(line) < at.distance2D(Builder::gHomePos)))
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
	// Dispatching above the ordinary ladder skipped every threat veto that the
	// normal mex path runs, so the crew walked into fire that an ordinary
	// constructor would have refused -- apexearth, watching: "cons seem really
	// dumb, dark green just walking its cons off to die instead of making
	// economy." A crew is a standing job, not a licence to ignore the map.
	const AIFloat3 where = aiEconomyMgr.GetMexSpotPos(spot);
	if (Builder::OnMap(where)) {
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
//
// apexearth: "front line defenses are better but still have gaps that are
// continuously a problem. front line lacked jammers for a long time, and there
// were no nano turrets to support/heal the front line."
//
// A turret is the thing that fights, so it comes first. A construction turret
// behind it repairs everything in its radius, which is the cheapest way to keep
// a line standing. A jammer (armjamt 240, corjamt 115, legjam 140) hides the lot
// from radar. Jammers are also in build_chain.json, hung off armanni -- a hub
// only fires when its exact parent FINISHES, which is why they arrived late or
// not at all.
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

// A front line is a LATE-GAME structure.
//
// apexearth: "frontline defense for LATE GAME, not for early game... lower
// defense for defending the mexes early game, killing the raiding parties", and
// on why: "I KNOW they're good once we hit T3... that wall of pulsars is great...
// but in the lesser defenses the enemy is often able to concentrate their fire
// and overwhelm any one area."
//
// That is a statement about mass, not about tier. Scattered cheap turrets are
// defeated in detail because each fights alone; a T3 wall works because the
// pieces cover each other and outrange the approach. So spreading lesser
// defence along a line is strictly worse than either massing it or not buying
// it -- and we were doing exactly that, at 22.9% of our metal against stock's
// 13.1% while spending ZERO on T3.
//
// Early defence is MexGuard's job instead: cheap turrets on the mexes that are
// actually being raided.
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
	if (!Builder::OnMap(site))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(
			isTurret ? Task::BuildType::DEFENCE : Task::BuildType::NANO,
			Task::Priority::NORMAL, tower, site, 0.f));
	if (post is null)
		return null;
	if (isTurret)
		gFrontPlaced.insertLast(spot);
	AiLog(Factory::T() + "apex: crew front " + unit.circuitDef.GetName()
		+ " -> " + tower.GetName() + " posts=" + gFrontPlaced.length());
	return post;
}

// Fill a vacancy from the economy pool.
//
// Enlist only ever sees NEW constructors, so a crew that is wiped out stays
// empty until the factory happens to make another one -- measured on the first
// run of this, a player sat at mex=0 with five economy constructors standing.
// Promoting is not the role-churn the comment on Enlist warns about: that is
// about a unit being tempted away from its job, and this is the same direction
// the crew already moves in when the spots run out, just backwards.
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

// The crew is a T1-phase institution. apexearth: "mex crew doesn't need to exist
// after the game is T2 stage I think."
//
// Members are not deleted, they RETIRE the same way a member does when the spots
// run out -- by where they are standing -- so the ones already forward become
// front constructors instead of walking home.
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
