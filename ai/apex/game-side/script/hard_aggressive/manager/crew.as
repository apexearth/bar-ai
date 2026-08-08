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

enum Role { ECO = 0, MEX = 1, FRONT = 2 };

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
	const int role = (CountOf(MEX) < MEX_CREW) ? MEX : ECO;
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
IUnitTask@ FrontWork(CCircuitUnit@ unit)
{
	if (RoleOf(unit) != FRONT)
		return null;
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	// ContestTower returns null for a T1 constructor once we are past T1 tier --
	// apexearth does not want light lasers built late. Such a member falls
	// through to the ordinary ladder rather than building something worthless.
	CCircuitDef@ tower = Builder::ContestTower(unit);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;

	AIFloat3 line;
	if (!Front::FrontNear(unit.GetPos(ai.frame), line))
		return null;
	// Stand off from the line toward home, so the tower covers the approach
	// rather than being placed in the middle of the enemy's half.
	AIFloat3 spot;
	if (!Builder::StandoffPos(unit, line, spot))
		return null;
	for (uint i = 0; i < gFrontPlaced.length(); ++i) {
		if (gFrontPlaced[i].distance2D(spot) < FRONT_SPACING)
			return null;
	}
	if (!Builder::AreaNeedsDefence(spot))
		return null;

	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, tower, spot, Builder::DEF_SHAKE));
	if (post is null)
		return null;
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
	AiLog(Factory::T() + "apex: crew mex=" + CountOf(MEX)
		+ " front=" + CountOf(FRONT) + " eco=" + CountOf(ECO)
		+ " tracked=" + gId.length() + " posts=" + gFrontPlaced.length()
		+ " mexesBuilt=" + gMexBuilt
		+ " died mex/front/eco=" + gDiedMex + "/" + gDiedFront + "/" + gDiedEco);
	if (gDeathKind.length() > 0)
		AiLog(Factory::T() + "apex: con deaths by job" + DeathReport());
}

}  // namespace Crew
