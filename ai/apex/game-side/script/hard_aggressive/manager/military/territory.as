namespace Military {

//------------------------------------------------------------------------------
// Defence gating.
//
// First, what is not available. Checked against CircuitAI's script/*.cpp:
// CThreatMap is registered but exposes only ApplyRange(), CInfluenceMap is not
// registered at all, CMetalManager is not registered so the `cluster` argument
// cannot be resolved into anything, and CEnemyManager exposes four global scalars
// -- GetEnemyPos() and GetEnemyGroups() exist in C++ and are not bound. There is
// no way to ask "how close is the enemy to this position" from AngelScript.
// mobileThreat is a whole-map sum over every known enemy mobile unit; using it as
// a stand-in for proximity would be the same class of error as reading
// GetTeamMetalFill() == 1 as "the lead is rich".
//
// Second, what the C++ underneath already does. DefaultMakeDefence bails on ally
// zones, raises a cluster to the full defender list when two neighbouring
// clusters read hot on the threat map or when our influence at the site is zero,
// caps spend at amountFactor * min(avg metal income, avg energy income) * eco
// factor, only adds AA once enemy air cost is nonzero, and orients the towers
// along GetEnemyPos(). The positional judgement
// exists -- it sits one level below this hook. So the hook's real job is deciding
// whether to ask at all, and its honest inputs for that are global.
//
// Hence: ask once the enemy actually fields an army, and skip while it does
// not. Sites outside our own footprint bypass that gate; see below for why
// that is a proxy rather than proximity.
//------------------------------------------------------------------------------
// behaviour.json sets quota.attack = 15 -- the group threat at which BARb itself
// rates a force worth attacking. Read that as one enemy player's worth of fielded
// army and scale it by the number of enemy teams, because mobileThreat sums the
// whole enemy team: an unscaled constant is met by one scouting wave in an 8v8
// and by a genuine push in a 1v1, which is backwards.
const float PORC_THREAT_PER_ENEMY = 15.f;
// Deadband on the way back down. Without it the gate flips every time a raider
// dies and porc tasks get enqueued and aborted in alternation.
const float PORC_RELEASE = 0.8f;

// CONTROLLED TERRITORY, and its forward edge.
//
// The grid already exists and is not ours to invent: CMilitaryManager walks the
// metal clusters and calls this hook for every one our side has taken
// (UpdateDefenceTasks only calls MakeDefence for IsClusterQueued/IsClusterFinished,
// and finishedCount counts ALLY mexes, not just ours). So the set of positions
// this hook is offered IS our side's territory, and the members of it nearest the
// enemy are its forward edge.
//
// This deliberately replaces the old anchor-centroid "frontier" test, which
// measured distance from our own early mass and so read a rear expansion as a
// frontier, and the gadget-published front, which is a point on the line from our
// centroid to theirs -- a lane, absent entirely outside this harness because
// dev_team_income.lua does not exist in a hosted game.
const float BORDER_BAND = 1200.f;

bool  gPorcArmed = false;

array<int>      gSiteId;
array<AIFloat3> gSitePos;

void NoteSite(int cluster, const AIFloat3& in pos)
{
	for (uint i = 0; i < gSiteId.length(); ++i) {
		if (gSiteId[i] == cluster) {
			gSitePos[i] = pos;
			return;
		}
	}
	gSiteId.insertLast(cluster);
	gSitePos.insertLast(pos);
}

// The rank-th of our holdings, counted from the enemy inwards. rank 0 is the tip
// of our territory.
//
// A site further from home than the enemy centroid is not ours to hold -- that
// is an ally's ground on the far side of the map, and a tower we send a builder
// across the map to place is a tower that arrives after the fight.
//
// Cover the border, do not crowd one bearing: ranking sites purely by distance
// to aiEnemyMgr.GetEnemyPos() -- a SINGLE point, the enemy centroid -- made
// every tower march toward the same compass direction, and whichever flank the
// centroid did not point at got nothing however much of our territory sat on
// it.
//
// Coverage instead: among the sites on our forward edge, take the one that is
// least defended already. gFencePos is the register of every defence we own,
// so "least defended" is a real count and not a guess. Distance to the enemy
// still decides WHICH sites are eligible -- the forward edge is still the
// front -- but among those, the emptiest ground wins.
const float COVER_RADIUS = 900.f;

// "Nearest to the enemy centroid" alone picked a lone forward expansion mex
// over the base itself whenever that expansion happened to be closer to
// GetEnemyPos() -- a real hit for the big gun (armanni/cordoom/legbastion,
// the first high-value tower this AI builds) landing in a map corner while
// the base it was meant to anchor got nothing. RebuildFront's ray model
// already knows which of our sites are actually on the contested line
// (OnBorder); a site we hold that no ray ever crossed is an unpressured
// outpost, not a front, however close it sits to the enemy's average
// position. Gate eligibility on that before ranking by distance.
bool BorderPos(AIFloat3& out p, uint rank)
{
	if (gSitePos.length() == 0)
		return false;
	AIFloat3 e = aiEnemyMgr.GetEnemyPos();
	const float reach = Builder::gHomeSet ? Builder::gHomePos.distance2D(e) : -1.f;
	RebuildFront();
	const bool haveFront = gFrontValid && (gRayR.length() > 0);

	// The forward edge: the nearest eligible site to the enemy sets the band.
	float edge = -1.f;
	for (uint i = 0; i < gSitePos.length(); ++i) {
		if ((reach > 0.f) && (gSitePos[i].distance2D(Builder::gHomePos) > reach))
			continue;
		if (haveFront && !OnBorder(gSitePos[i]))
			continue;
		const float d = gSitePos[i].distance2D(e);
		if ((edge < 0.f) || (d < edge))
			edge = d;
	}
	// No site sits on an established line yet -- rank 0 falls back to home,
	// which is where a first defence belongs before there is a real front to
	// anchor it to, rather than the nearest-to-enemy site by default.
	if (edge < 0.f) {
		if ((rank == 0) && Builder::gHomeSet) {
			p = Builder::gHomePos;
			return true;
		}
		return false;
	}

	// COVERAGE, not a wall on one bearing.
	//
	// An earlier version restricted candidates to sites within one band of the
	// forward edge, which fixed WHICH forward site got the tower but left the
	// flanks ineligible, so towers still stacked in one place and the enemy
	// still walked around them into the economy.
	//
	// Every site on the established line is eligible (all of them, once we have
	// one -- see haveFront above). Score = (defences already near it + 1) x
	// distance to the enemy, lowest wins. Two properties fall out of that product:
	// an UNDEFENDED site always outranks a defended one at the same distance, so
	// cover spreads before it thickens; and among equally undefended sites the
	// most exposed one wins, so it spreads toward the threat rather than into the
	// rear. A site that already has three towers must be three times closer to the
	// enemy to beat a bare one.
	float prevScore = -1.f;
	AIFloat3 pick;
	bool have = false;
	for (uint r = 0; r <= rank; ++r) {
		float bestScore = -1.f;
		bool found = false;
		for (uint i = 0; i < gSitePos.length(); ++i) {
			if ((reach > 0.f) && (gSitePos[i].distance2D(Builder::gHomePos) > reach))
				continue;
			if (haveFront && !OnBorder(gSitePos[i]))
				continue;
			const float d = gSitePos[i].distance2D(e);
			const float cover = float(FenceCountNear(gSitePos[i], COVER_RADIUS));
			const float score = (cover + 1.f) * d;
			if (score <= prevScore)
				continue;                       // claimed by an earlier rank
			if (!found || (score < bestScore)) {
				bestScore = score;
				pick = gSitePos[i];
				found = true;
			}
		}
		if (!found)
			break;
		prevScore = bestScore;
		have = true;
	}
	if (!have)
		return false;
	p = pick;
	return true;
}

// THE FRONT IS BETWEEN US AND THEM, NOT WHEREVER WE HAPPEN TO HAVE BUILT.
//
// This used to be measured against BorderPos(edge, 0), which is the closest of
// OUR OWN defence sites to the enemy -- a self-referential definition. With
// everything we own sitting at home, home became the border and every rear
// tower passed the check.
//
// So it is geometry now: how far along the line from our base to theirs a
// position sits. 0 is our base, 1 is theirs, and anything past FRONT_FRACTION
// counts as forward. GetEnemyPos is the centroid of all enemies, which is a poor
// answer to "where is that one raider" and a perfectly good answer to "which way
// is forward" -- the only thing it is used for here.
const float FRONT_FRACTION = 0.30f;

// WHERE OUR TERRITORY ACTUALLY IS, not where we spawned.
//
// Everything positional used to measure from Builder::gHomePos, the START
// position. It never moves, so as the base grows forward the origin stays
// behind it and a tower behind the real base still read as "forward".
//
// gSitePos is every metal cluster our side holds, which this file's own comment
// already calls our territory: CMilitaryManager offers this hook one position
// per cluster we have taken. Its centroid is where we are NOW. The start
// position is the fallback for the opening, before we hold anything.
AIFloat3 TerritoryCentre()
{
	if (gSitePos.length() == 0)
		return Builder::gHomePos;
	float x = 0.f;
	float z = 0.f;
	for (uint i = 0; i < gSitePos.length(); ++i) {
		x += gSitePos[i].x;
		z += gSitePos[i].z;
	}
	const float n = float(gSitePos.length());
	AIFloat3 c = AIFloat3(x / n, 0.f, z / n);
	return OnMap(c) ? c : Builder::gHomePos;
}

float ForwardFraction(const AIFloat3& in pos)
{
	if (!Builder::gHomeSet)
		return 0.f;
	const AIFloat3 home = TerritoryCentre();
	const AIFloat3 e = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(e))
		return 0.f;
	const float dx = e.x - home.x;
	const float dz = e.z - home.z;
	const float span = dx * dx + dz * dz;
	if (span < NEAR_ZERO)
		return 0.f;
	return ((pos.x - home.x) * dx + (pos.z - home.z) * dz) / span;
}

// THE FRONT LINE, AS A CURVE ACROSS THE MAP, COMPUTED FROM THE BATTLEFIELD.
//
// Not one marker, a CURVE. The influence map is engine-side and always present
// -- GetNetInflAt is ally minus enemy -- so the front is where that crosses
// zero: "where OUR territory ends and the ENEMY'S begins". Sampled once per
// lane across the width of the map, the crossings form a line that bulges
// where they have pushed into us and recedes where we have pushed into them.
//
// Nothing here is a gadget. The old source read ai_frontx_<team>, published by
// dev_team_income.lua, which exists only in BAR.sdd, so in a hosted game it
// returned nothing at all.
//
// Forward is the bearing from our base to the enemy centroid: a poor answer to
// "where is that raider", a fine one to "which way is the enemy", which is all
// it is asked. Lanes run perpendicular to it. Before contact there is no
// crossing and the opening answer is the one the start boxes give -- halfway.
// LANES SPAN THE MAP, they are not a fixed width: the count is fixed and the
// SPACING follows the map's diagonal, so the line always reaches both edges
// whatever it is playing on -- a fixed-width lane visibly stopped a third of
// the way down an 8v8 map.
const int FRONT_LANES = 6;            // each side of centre, so 13 lanes

float FrontLaneGap()
{
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	const float diag = sqrt(w * w + h * h);
	return diag / float(2 * FRONT_LANES);
}
const int   FRONT_SAMPLES  = 14;
const float FRONT_SCAN_END = 1.15f;   // a little past their centroid
const float FRONT_BAND     = 0.18f;   // how wide "on the line" is, as a fraction
const float FRONT_SETBACK  = 0.12f;   // build this far inside it, not on it

// THE FRONT IS A RING AROUND WHAT WE HOLD, NOT A LINE ACROSS ONE BEARING.
//
// Lanes are laid perpendicular to ONE bearing -- our centre to the enemy
// CENTROID -- so the front they describe is always a straight line facing one
// direction. A team in a corner is surrounded across ninety degrees or more,
// and the average of all those enemies points somewhere down the middle, so
// the lanes end up perpendicular to a direction no individual enemy is
// actually on.
//
// Sampling RADIALLY has no preferred direction: one ray per bearing, each
// finding its own crossing, and the shape that falls out is whatever the
// situation is -- a straight line when the enemy is on one side, an arc cutting
// off a corner when we are boxed into one, a full ring when surrounded. It is
// also less code than the lane version: no perpendicular, no lane gap, no map
// diagonal.
const int FRONT_RAYS = 24;            // every 15 degrees
// Radius, in elmos, at which each bearing's ray meets the front. Index 0 points
// along +x and they run counter-clockwise.
array<float> gRayR;
// The same per bearing, but as far out as a BUILDER may actually work.
array<float> gRaySafe;
// DID THIS BEARING ACTUALLY MEET ANYBODY. A ray that ran its whole length
// without finding enemy influence, or that walked off the map, has no front on
// it -- it is our own rear, or the edge of the world. Emitting every ray as a
// build point turns the ring into a literal circle of towers around the base,
// most of them facing nothing; sampling all the way round is still right --
// that is what lets a corner read as an arc -- but only the contested arc of
// it is the front.
array<bool> gRayHot;
// DID THIS BEARING STOP AT THE MAP EDGE. A ray that walks off the map breaks out
// of the sample loop before it can meet anybody, so it records hot=false and both
// FrontLineSpots and FrontBuildSpots skip it -- the two failures are
// indistinguishable in gRayHot alone, and they need opposite answers.
array<bool> gRayWall;

// THE RING'S OWN SAMPLE COUNT. The march below stops at the edge of our own
// territory instead of running to the map edge, so most rays break after a
// handful of samples and a finer step costs almost nothing -- while the step is
// what the radius is quantised to, and at 14 samples over half the map diagonal
// that was 366 elmos on a 16x12 map.
const int RING_SAMPLES = 28;
// TWO FIELDS, TWO BARS -- never their difference.
//
// GetNetInflAt is allyInfl - enemyInfl, both refilled to INFL_BASE = 0 every
// update and accumulated only from friendly units and KNOWN enemies
// (CInfluenceMap::Prepare/AddEnemy). So it reads exactly 0 over every cell
// nobody has been near, and a `< 0` test walks straight through no-man's-land to
// the first cell an enemy is standing in. Same trap Front::Scan documents: net
// influence reads 77 beside our base and exactly 0 on ground nobody has been
// near, and most of the map is the second kind.
//
// So ally and enemy are tested SEPARATELY, each against a share of its own peak
// over this same sample set. The two fields are not on one scale -- ally counts
// every armed unit the whole ally team owns, enemy counts only what we have
// seen -- so one absolute floor cannot serve both.
//
// The fractions are Front::TERRITORY_FRAC and Front::FOE_FRAC, restated rather
// than referenced: manager/military.as is included before manager/frontline.as
// (see main.as), so the Front:: namespace does not exist yet at this line and
// naming it is a `No matching symbol` that disables the whole variant.
const float RING_ALLY_FRAC  = 0.03f;
const float RING_ALLY_FLOOR = 1.0f;
const float RING_FOE_FRAC   = 0.10f;
const float RING_FOE_FLOOR  = 1.0f;
float gRingAllyBar = RING_ALLY_FLOOR;
float gRingFoeBar  = RING_FOE_FLOOR;

// Per lane: the fraction along home->enemy at which that lane's influence
// crosses. Index 0 is the leftmost lane.
array<float> gFrontLane;
// How far out a BUILDER can actually work in each lane, as a fraction of the
// same axis. Not the same question as where the line is, and it is the one that
// decides whether a tower can exist: IBuilderTask::FindBuildSite searches with a
// CanReachAtSafe predicate, which rejects any cell whose builder threat is above
// THREAT_MIN, so an order past this point is refused by the engine's own site
// search and left queued with nobody on it.
//
// Threat does not time out. CMapManager::HostileInLOS keeps an enemy's threat
// until we have line of sight on where it was and it is gone, or it dies -- so
// this edge moves outward when the army takes ground, and not otherwise.
array<float> gFrontSafe;
int gFrontStamp = -1;
AIFloat3 gFrontFwd;      // home -> enemy, unnormalised (the axis' own length)
AIFloat3 gFrontSide;     // unit perpendicular
AIFloat3 gFrontHome;
bool gFrontValid = false;

void RebuildFront()
{
	if ((gFrontStamp >= 0) && (ai.frame - gFrontStamp < 30))
		return;
	gFrontStamp = ai.frame;
	gFrontValid = false;
	gFrontLane.resize(0);
	gFrontSafe.resize(0);

	if (!Builder::gHomeSet)
		return;
	const AIFloat3 home = TerritoryCentre();
	const AIFloat3 e = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(e))
		return;
	AIFloat3 fwd = e - home;
	if (fwd.SqLength2D() < NEAR_ZERO)
		return;
	AIFloat3 side = AIFloat3(-fwd.z, 0.f, fwd.x);
	side.SafeNormalize2D();

	gFrontHome = home;
	gFrontFwd = fwd;
	gFrontSide = side;

	for (int lane = -FRONT_LANES; lane <= FRONT_LANES; ++lane) {
		const AIFloat3 origin = home + side * (float(lane) * FrontLaneGap());
		float found = -1.f;
		float ours = -1.f;
		float safe = 0.f;
		for (int i = 1; i <= FRONT_SAMPLES; ++i) {
			const float t = FRONT_SCAN_END * float(i) / float(FRONT_SAMPLES);
			const AIFloat3 p = origin + fwd * t;
			if (!OnMap(p))
				break;
			// THE SAFE GROUND CLOSEST TO THE LINE: the FURTHEST workable sample,
			// not the first threatened one. The engine's own CanReachAtSafe tests
			// threat at the DESTINATION plus whether a path exists, not a clear
			// straight line, so stopping at the first threat wrongly collapsed
			// the whole lane onto the base whenever one raider sat close in.
			//
			// THE SAME BAR THE ENGINE USES: CanReachAtSafe tests
			// `GetBuilderThreatAt(pos) > THREAT_MIN` (1.0, util/Defines.h), and
			// the accessor has already subtracted THREAT_BASE, so testing `> 0`
			// instead put the safe edge one step from the base in every lane.
			if (ai.GetBuilderThreatAt(p) <= ai.GetTunable("apex_build_threat_bar", 1.f))
				safe = t;
			// EMPTY GROUND IS NOBODY'S, NOT THEIRS. GetNetInflAt is ally minus
			// enemy, so ground neither side has been near reads exactly 0, and
			// testing `<= 0` called the first such sample the crossing -- putting
			// the front one step from our own base on any flank not yet walked.
			const float inf = ai.GetNetInflAt(p);
			if (inf > 0.f) {
				ours = t;      // still ours out to here
				continue;
			}
			if (inf < 0.f) {
				found = t;     // theirs: this is the crossing
				break;
			}
			// exactly 0: no man's land, keep walking
		}
		// Held all the way to the last positive sample and never met them: the line
		// is out past there, not back at the base.
		if ((found < 0.f) && (ours > 0.5f))
			found = ours;
		// A lane with no crossing is one we hold all the way, or one nobody has
		// contested. Halfway is the start-box answer and is right for both.
		gFrontLane.insertLast((found < 0.f) ? 0.5f : found);
		gFrontSafe.insertLast(safe);
	}
	RebuildRing(home);
	gFrontValid = true;
	FrontDiag();
}

// One ray per bearing, each finding THE EDGE OF WHAT WE HOLD on that bearing.
//
// It used to walk until GetNetInflAt went negative, which is not the edge of
// our territory -- it is the first cell where a KNOWN enemy outweighs us, i.e.
// their own front rank. Every ray therefore crossed the whole of no-man's-land
// (net influence is exactly 0 there) and stopped on top of them, sending
// constructors to build too far forward and get killed doing it.
//
// Now: our own influence says how far out we hold, theirs says where they are,
// each against its own bar, and the radius is the last sample that was ours and
// free of them. That answer needs no vision at all -- it exists from minute one
// and it does not move when a raid drives past -- which is the same reason
// Front:: settled on the outer edge of our own influence region after three
// definitions that needed to see the enemy died against measurement.
void RebuildRing(const AIFloat3& in home)
{
	gRayR.resize(0);
	gRaySafe.resize(0);
	gRayHot.resize(0);
	gRayWall.resize(0);
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	const float reach = sqrt(w * w + h * h) * 0.5f;   // half the map diagonal
	const float step = reach / float(RING_SAMPLES);
	const float bar = ai.GetTunable("apex_build_threat_bar", 1.f);

	// NOTHING BEHIND US IS FRONT.
	//
	// Firmer than asking the influence map, which answers about this tick: a
	// bearing pointing away from every enemy cannot become the front line
	// because there is nobody back there to make one. Excluding the rear half
	// outright also stops the ring closing on itself, which is what wrapped the
	// drawn line around our own half of the map.
	//
	// apex_front_rear_arc=1 restores the full ring for a genuinely surrounded
	// base.
	const bool rearToo = ai.GetTunable("apex_front_rear_arc", 0.f) > 0.f;
	AIFloat3 toEnemy = aiEnemyMgr.GetEnemyPos() - home;
	const bool haveBearing = toEnemy.SqLength2D() > NEAR_ZERO;
	const float sep = haveBearing ? sqrt(toEnemy.SqLength2D()) : 0.f;
	if (haveBearing)
		toEnemy.SafeNormalize2D();

	// AND NOT PAST THE ENEMY. GetAllyInflAt is ally-WIDE, so a bearing running
	// sideways along the team's holdings never leaves friendly influence and would
	// report a radius of half the map -- ground an ally holds, drawn as our front
	// and offered as our build line. BorderPos in this same file already states
	// the rule this reuses: "A site further from home than the enemy centroid is
	// not ours to hold -- that is an ally's ground on the far side of the map."
	float march = reach;
	if (haveBearing && (sep > step) && (sep < march))
		march = sep;

	// PASS 1: the two peaks, over exactly the samples pass 2 will march. Every
	// read is OnMap-guarded -- CInfluenceMap::PosToXZ does no bounds check at all
	// (`x = (int)pos.x / squareSize`) and indexes enemyInfl[z * width + x] off the
	// raw position, the same unchecked pattern that made GetBuilderThreatAt kill
	// the engine at frame 3.
	float maxAlly = 0.f;
	float maxFoe = 0.f;
	for (int r = 0; r < FRONT_RAYS; ++r) {
		const float ang = 6.2831853f * float(r) / float(FRONT_RAYS);
		const AIFloat3 dir = AIFloat3(cos(ang), 0.f, sin(ang));
		if (!rearToo && haveBearing
			&& ((dir.x * toEnemy.x + dir.z * toEnemy.z) <= 0.f))
			continue;
		for (int i = 1; i <= RING_SAMPLES; ++i) {
			const float d = step * float(i);
			if (d > march)
				break;
			const AIFloat3 p = home + dir * d;
			if (!OnMap(p))
				break;
			const float a = ai.GetAllyInflAt(p);
			const float f = ai.GetEnemyInflAt(p);
			if (a > maxAlly) maxAlly = a;
			if (f > maxFoe) maxFoe = f;
		}
	}
	gRingAllyBar = maxAlly * RING_ALLY_FRAC;
	if (gRingAllyBar < RING_ALLY_FLOOR)
		gRingAllyBar = RING_ALLY_FLOOR;
	// NOTHING SEEN IS NOT NOTHING THERE. With maxFoe at 0 the bar sits on its
	// floor and no sample can ever reach it, so the ray falls through to the ally
	// test and answers "our territory ends here" -- a real measurement rather than
	// a guess about an enemy we have not found. That is the point of splitting the
	// two tests: a rear player, whose own influence map holds no enemy at all,
	// still gets a line instead of concluding there is no front.
	gRingFoeBar = maxFoe * RING_FOE_FRAC;
	if (gRingFoeBar < RING_FOE_FLOOR)
		gRingFoeBar = RING_FOE_FLOOR;

	// PASS 2: march.
	for (int r = 0; r < FRONT_RAYS; ++r) {
		const float ang = 6.2831853f * float(r) / float(FRONT_RAYS);
		const AIFloat3 dir = AIFloat3(cos(ang), 0.f, sin(ang));
		if (!rearToo && haveBearing
			&& ((dir.x * toEnemy.x + dir.z * toEnemy.z) <= 0.f))
		{
			gRayR.insertLast(reach);
			gRaySafe.insertLast(0.f);
			gRayHot.insertLast(false);
			gRayWall.insertLast(false);
			continue;
		}
		float edge = 0.f;        // last sample that was still ours
		float safe = 0.f;
		bool wall = false;       // did it run out of map
		for (int i = 1; i <= RING_SAMPLES; ++i) {
			const float d = step * float(i);
			if (d > march)
				break;
			const AIFloat3 p = home + dir * d;
			if (!OnMap(p)) {
				wall = true;
				break;
			}
			// THEM FIRST, so a cell they hold can never be recorded as ours. This
			// is also what keeps the line out of the battle itself: where both
			// fields are up, the last ground a builder can be sent to is the cell
			// BEFORE the one they are standing in.
			if (ai.GetEnemyInflAt(p) >= gRingFoeBar)
				break;
			if (ai.GetAllyInflAt(p) < gRingAllyBar)
				break;   // our territory ended at the previous sample
			edge = d;
			// Only inside our own ground: past the radius the answer is not used,
			// and this is the expensive read of the three.
			if (ai.GetBuilderThreatAt(p) <= bar)
				safe = d;
		}
		// A bearing we hold nothing on carries `reach`, not 0. OnBorder compares a
		// position against gRayR on its own bearing WITHOUT consulting gRayHot, so
		// a 0 here would make every position in that sector read "on the border" --
		// this is the same sentinel the rear arc above already uses.
		gRayR.insertLast((edge > 0.f) ? edge : reach);
		gRaySafe.insertLast(safe);
		gRayHot.insertLast(edge > 0.f);
		gRayWall.insertLast(wall);
	}

	// THE WALL IS PART OF THE LINE, NOT THE END OF IT. A bearing that ran out of
	// map records hot=false, and FrontLineSpots/FrontBuildSpots skip a cold
	// bearing outright -- so for a player sitting against the map edge the whole
	// sector between us and that wall emits no build point at all. It is also the
	// sector a raider hugs to get behind us.
	//
	// A wall bearing whose NEIGHBOUR met the enemy is the same front, ending at
	// the wall, so it adopts that classification. Seeded from copies so the
	// adoption cannot cascade round the ring in whichever direction the loop
	// happens to run.
	//
	// Its radius is then capped at that neighbour's: a ray that left the map at
	// long range carries the map's geometry, not the battlefield's, and would
	// otherwise place a point deeper than the front it is borrowing from.
	// It adopts the neighbour's SAFE EDGE as well as its radius. Under the older
	// rule a wall ray accumulated `safe` for every on-map sample before it broke;
	// `safe` is now only recorded inside our own territory, so a wall ray holding
	// none of its own would carry safe=0 and FrontLineSpots would drop it again
	// for a different reason. Where the borrowed point actually lands is still
	// re-checked by Builder::ThreatFor and FindBuildSiteNear before anything is
	// ordered there.
	array<bool> seed = gRayHot;
	array<float> seedR = gRayR;
	array<float> seedS = gRaySafe;
	for (uint i = 0; i < gRayHot.length(); ++i) {
		if (seed[i] || !gRayWall[i])
			continue;
		const uint prev = (i + gRayHot.length() - 1) % gRayHot.length();
		const uint next = (i + 1) % gRayHot.length();
		uint src = 0;
		bool haveSrc = false;
		if (seed[prev] && !gRayWall[prev]) {
			src = prev;
			haveSrc = true;
		}
		if (seed[next] && !gRayWall[next]
			&& (!haveSrc || (seedR[next] < seedR[src])))
		{
			src = next;
			haveSrc = true;
		}
		if (!haveSrc)
			continue;
		gRayHot[i] = true;
		if (gRayR[i] > seedR[src])
			gRayR[i] = seedR[src];
		if (gRaySafe[i] <= 0.f)
			gRaySafe[i] = seedS[src];
		if (gRaySafe[i] > gRayR[i])
			gRaySafe[i] = gRayR[i];
	}
}

// Which ray a position falls on.
int RayOf(const AIFloat3& in pos)
{
	const float dx = pos.x - gFrontHome.x;
	const float dz = pos.z - gFrontHome.z;
	float ang = atan2(dz, dx);
	if (ang < 0.f)
		ang += 6.2831853f;
	int r = int(ang / 6.2831853f * float(FRONT_RAYS) + 0.5f);
	if (r >= FRONT_RAYS)
		r = 0;
	if (r < 0)
		r = 0;
	return r;
}

// WHERE THE LINE ACTUALLY SITS. Every reading of the defence telemetry so far has
// had to infer this: a tower measured at 0.03 of the way to the enemy is either a
// placement rule ignoring the front or a front that really is at our doorstep, and
// the two are indistinguishable from the outside.
int gNextFrontLog = 0;
void FrontDiag()
{
	if (ai.frame < gNextFrontLog)
		return;
	gNextFrontLog = ai.frame + 30 * SECOND;
	float lo = 9.f;
	float hi = -9.f;
	float sum = 0.f;
	int uncontested = 0;
	for (uint i = 0; i < gFrontLane.length(); ++i) {
		const float t = gFrontLane[i];
		sum += t;
		if (t < lo) lo = t;
		if (t > hi) hi = t;
		if (t == 0.5f) ++uncontested;
	}
	// IS THE BINDING TELLING THE TRUTH? "There is no safe ground forward" is a
	// strong claim resting entirely on GetBuilderThreatAt, which this repo has
	// already caught reading nonsense once. Raw values along the axis, including
	// our own base, which must read ~0 early or the reading is not what we think.
	string ray = "";
	for (int k = 0; k <= 5; ++k) {
		const float t = 0.1f * float(k);
		const AIFloat3 p = gFrontHome + gFrontFwd * t;
		ray += OnMap(p) ? formatFloat(ai.GetBuilderThreatAt(p), "", 0, 1) : "-";
		ray += " ";
	}
	float safeSum = 0.f;
	float safeMax = 0.f;
	for (uint i = 0; i < gFrontSafe.length(); ++i) {
		safeSum += gFrontSafe[i];
		if (gFrontSafe[i] > safeMax)
			safeMax = gFrontSafe[i];
	}
	const float sn = float(gFrontSafe.length());
	const float n = float(gFrontLane.length());
	AiLog(Factory::T() + "apex: front-diag lanes=" + gFrontLane.length()
		+ " ray[0..0.5]=" + ray
		+ " safeMean=" + formatFloat((sn > 0.f) ? safeSum / sn : 0.f, "", 0, 2)
		+ " safeMax=" + formatFloat(safeMax, "", 0, 2)
		+ " mean=" + formatFloat((n > 0.f) ? sum / n : 0.f, "", 0, 2)
		+ " min=" + formatFloat(lo, "", 0, 2)
		+ " max=" + formatFloat(hi, "", 0, 2)
		+ " uncontested=" + uncontested
		+ " gap=" + formatFloat(FrontLaneGap(), "", 0, 0));

	// THE RING, WHICH IS WHAT ACTUALLY SITES DEFENCE. Everything above describes
	// the LANE scan; FrontLineSpots, FrontCurve and OnBorder all read gRayR, and
	// nothing reported it -- so "the towers are too far up" and "the front is
	// where we think it is" could not be told apart from a log.
	//
	// r/sep is the radius as a share of the home->enemy separation: the fraction
	// of the way to the enemy this line sits at, directly comparable with
	// front-diag's own mean.
	float rSum = 0.f;
	float rMin = -1.f;
	float rMax = 0.f;
	float sSum = 0.f;
	int hotN = 0;
	for (uint i = 0; i < gRayR.length(); ++i) {
		if ((i >= gRayHot.length()) || !gRayHot[i])
			continue;
		++hotN;
		rSum += gRayR[i];
		if ((rMin < 0.f) || (gRayR[i] < rMin))
			rMin = gRayR[i];
		if (gRayR[i] > rMax)
			rMax = gRayR[i];
		if ((i < gRaySafe.length()) && (gRayR[i] > 1.f))
			sSum += gRaySafe[i] / gRayR[i];
	}
	float axis = sqrt(gFrontFwd.SqLength2D());
	if (axis < 1.f)
		axis = 1.f;
	const float hn = float((hotN > 0) ? hotN : 1);
	AiLog(Factory::T() + "apex: ring-diag rays=" + hotN + "/" + gRayR.length()
		+ " sep=" + int(axis)
		+ " r/sep mean=" + formatFloat(rSum / hn / axis, "", 0, 2)
		+ " min=" + formatFloat(((rMin < 0.f) ? 0.f : rMin) / axis, "", 0, 2)
		+ " max=" + formatFloat(rMax / axis, "", 0, 2)
		+ " safe/r=" + formatFloat(sSum / hn, "", 0, 2)
		+ " bar=" + int(gRingAllyBar) + "/" + int(gRingFoeBar));

	GhostDiag();
}

// HOW MUCH OF THE ENEMY ARMY WE ARE COUNTING IS A MEMORY. GetEnemyCost never
// forgets a unit once registered, so the gap between it and the fresh sum is
// everything we saw once and have not seen since. Nothing acts on this yet --
// apex_ghost_weight defaults to 1.0, i.e. count ghosts in full, exactly as
// before -- but the fraction has to be measurable before it can be tuned.
void GhostDiag()
{
	const float raw = aiEnemyMgr.GetEnemyCost(Unit::Role::ASSAULT.type)
	                + aiEnemyMgr.GetEnemyCost(Unit::Role::RAIDER.type)
	                + aiEnemyMgr.GetEnemyCost(Unit::Role::RIOT.type)
	                + aiEnemyMgr.GetEnemyCost(Unit::Role::SKIRM.type);
	const float fresh = aiEnemyMgr.GetEnemyCostFresh(Unit::Role::ASSAULT.type)
	                  + aiEnemyMgr.GetEnemyCostFresh(Unit::Role::RAIDER.type)
	                  + aiEnemyMgr.GetEnemyCostFresh(Unit::Role::RIOT.type)
	                  + aiEnemyMgr.GetEnemyCostFresh(Unit::Role::SKIRM.type);
	AiLog(Factory::T() + "apexfoe: raw=" + int(raw)
		+ " fresh=" + int(fresh)
		+ " ghost%=" + int((raw > 1.f) ? (raw - fresh) * 100.f / raw : 0.f)
		+ " w=" + formatFloat(ai.GetTunable("apex_ghost_weight", 1.f), "", 0, 2));
}

// Which lane a position falls in, and how far along the axis it sits.
int LaneOf(const AIFloat3& in pos)
{
	const AIFloat3 d = pos - gFrontHome;
	const float off = d.x * gFrontSide.x + d.z * gFrontSide.z;
	int lane = int(off / FrontLaneGap() + (off >= 0.f ? 0.5f : -0.5f));
	if (lane < -FRONT_LANES)
		lane = -FRONT_LANES;
	if (lane > FRONT_LANES)
		lane = FRONT_LANES;
	return lane + FRONT_LANES;   // into array space
}

// Where the front sits in THIS position's lane, as a fraction along home->enemy.
float FrontFractionAt(const AIFloat3& in pos)
{
	RebuildFront();
	if (!gFrontValid || (gFrontLane.length() == 0))
		return 0.5f;
	return gFrontLane[LaneOf(pos)];
}

// The whole line, for callers that want the shape rather than one answer.
// THE FRONT LINE ITSELF: where our territory ends, per contested bearing.
//
// This is a statement about the battlefield, and it is what gets DRAWN. It is
// NOT a list of places to build -- conflating the two once showed build spots
// (clamped to the safe edge, dropping most bearings) instead of the front, so
// the drawn line was a few stubs near the base rather than the actual front.
bool FrontCurve(array<AIFloat3>& out pts)
{
	RebuildFront();
	pts.resize(0);
	if (!gFrontValid)
		return false;
	for (uint i = 0; i < gRayR.length(); ++i) {
		if ((i < gRayHot.length()) && !gRayHot[i])
			continue;   // no enemy on this bearing; see gRayHot
		const float ang = 6.2831853f * float(i) / float(FRONT_RAYS);
		const AIFloat3 dir = AIFloat3(cos(ang), 0.f, sin(ang));
		const AIFloat3 p = gFrontHome + dir * gRayR[i];
		if (OnMap(p))
			pts.insertLast(p);
	}
	return pts.length() > 0;
}

// A CONTINUOUS LINE, SPACED BY WHAT A TURRET CAN ACTUALLY SHOOT.
//
// Sample the arc at intervals of the turret's OWN weapon range, so a raider
// cannot pass between two of them. The spacing is read from the def via
// GetMaxRange rather than guessed -- the old FRONT_FENCE_SPREAD was a flat 700
// for an armllt that reaches 430 and a Rattlesnake that reaches much further,
// which leaves a hole in one case and wastes metal in the other.
//
// Sampling the ARC rather than the bearings is the point: 24 fixed bearings put
// points 785 elmos apart at radius 3000 and 130 apart at radius 500, so the same
// ring is full of holes far out and stacked up close. Arc length is the honest
// unit for "no gaps".
// EXTRA DENSITY AT THE MAP EDGE, DERIVED RATHER THAN GUESSED. A point deep in
// the interior is engaged from all sides; a point at the map edge only from
// the interior side, so it needs denser cover to match.
//
// The geometry is exact. A point on the line is engaged by every turret within
// range R OF IT ALONG THE LINE. In the interior that is a span of 2R -- R of
// line on each side. Within d < R of the map edge only min(R, d) of line exists
// on the outward side, because there is no map to put turrets on, so the
// covering span falls to R + min(R, d) -- as little as HALF, hard against the
// edge. Restoring equal cover means shrinking the spacing by that same ratio:
//
//     spacing(d) = spacing * (R + min(R, d)) / 2R
//
// 0.5x at the edge (double the turret density), 1.0x once a full turret range
// inland, linear between. Nothing is invented here: R is the very range the
// caller already spaced the line by, and the factor is the coverage deficit it
// is correcting.
float EdgeSpacing(const AIFloat3& in at, float spacing, float reach)
{
	if (reach < 1.f)
		return spacing;
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	float d = at.x;
	if (at.z < d)      d = at.z;
	if (w - at.x < d)  d = w - at.x;
	if (h - at.z < d)  d = h - at.z;
	if (d < 0.f)       d = 0.f;
	if (d > reach)     d = reach;
	return spacing * (reach + d) / (2.f * reach);
}

// The same coverage deficit EdgeSpacing corrects for, expressed as a multiplier
// on how much a turret at this point is WORTH: 1.0 inland, 2.0 hard against the
// wall, linear between. Spacing and value are the two ways to spend the deficit
// and they read it from one place.
float EdgeExposure(const AIFloat3& in at, float reach)
{
	if (reach < 1.f)
		return 1.f;
	const float s = EdgeSpacing(at, 1.f, reach);
	return (s > 0.f) ? (1.f / s) : 1.f;
}

bool FrontLineSpots(array<AIFloat3>& out pts, float spacing, float reach = 0.f)
{
	RebuildFront();
	pts.resize(0);
	if (!gFrontValid || (spacing < 1.f))
		return false;
	const float back = ai.GetTunable("apex_front_setback", FRONT_SETBACK);
	const bool useSafe = ai.GetTunable("apex_front_safe_edge", 1.f) > 0.f;
	const float minReach = ai.GetTunable("apex_front_min_reach", 0.5f);
	const float step = 6.2831853f / float(FRONT_RAYS);

	for (uint i = 0; i < gRayR.length(); ++i) {
		if ((i < gRayHot.length()) && !gRayHot[i])
			continue;
		const uint j = (i + 1) % gRayR.length();
		const bool pairHot = (j >= gRayHot.length()) || gRayHot[j];

		// This bearing's buildable radius, and the next one's, so the segment
		// between them can be filled at the requested spacing.
		float d0 = gRayR[i] * (1.f - back);
		if (useSafe && (i < gRaySafe.length()) && (gRaySafe[i] < d0))
			d0 = gRaySafe[i];
		if ((d0 <= 0.f) || (d0 < gRayR[i] * (1.f - back) * minReach))
			continue;
		float d1 = d0;
		if (pairHot) {
			d1 = gRayR[j] * (1.f - back);
			if (useSafe && (j < gRaySafe.length()) && (gRaySafe[j] < d1))
				d1 = gRaySafe[j];
			if (d1 <= 0.f)
				d1 = d0;
		}

		// How many turrets this segment of arc needs to be gap-free -- at the
		// spacing this part of the line needs, which is tighter near the map edge.
		// See EdgeSpacing.
		const float arc = step * ((d0 + d1) * 0.5f);
		const float midAng = 6.2831853f * (float(i) + 0.5f) / float(FRONT_RAYS);
		const AIFloat3 mid = gFrontHome
				+ AIFloat3(cos(midAng), 0.f, sin(midAng)) * ((d0 + d1) * 0.5f);
		const float useSpacing = EdgeSpacing(mid, spacing, reach);
		int n = int(arc / ((useSpacing > 1.f) ? useSpacing : spacing));
		if (n < 1)
			n = 1;
		for (int k = 0; k < n; ++k) {
			const float t = float(k) / float(n);
			const float ang = 6.2831853f * (float(i) + t) / float(FRONT_RAYS);
			const float d = d0 + (d1 - d0) * t;
			const AIFloat3 p = gFrontHome
					+ AIFloat3(cos(ang), 0.f, sin(ang)) * d;
			if (OnMap(p))
				pts.insertLast(p);
		}
	}
	return pts.length() > 0;
}

// WHERE A TOWER COVERING THAT LINE CAN ACTUALLY GO.
//
// Derived from the line, and different from it in three ways, each measured:
// pulled back by the setback so the builder is not parked in the fight; clamped
// to ground whose builder threat the engine's site search will accept, because
// past that the order is never staffed at all; and dropped entirely on bearings
// where that workable ground does not reach a decent share of the way out --
// otherwise every bearing collapses to the same short radius and the ring
// degenerates into a heap of turrets outside the base.
bool FrontBuildSpots(array<AIFloat3>& out pts)
{
	RebuildFront();
	pts.resize(0);
	if (!gFrontValid)
		return false;
	const float back = ai.GetTunable("apex_front_setback", FRONT_SETBACK);
	const bool useSafe = ai.GetTunable("apex_front_safe_edge", 1.f) > 0.f;
	const float minReach = ai.GetTunable("apex_front_min_reach", 0.5f);
	for (uint i = 0; i < gRayR.length(); ++i) {
		if ((i < gRayHot.length()) && !gRayHot[i])
			continue;
		const float ang = 6.2831853f * float(i) / float(FRONT_RAYS);
		const AIFloat3 dir = AIFloat3(cos(ang), 0.f, sin(ang));
		const float line = gRayR[i] * (1.f - back);
		float d = line;
		if (useSafe && (i < gRaySafe.length()) && (gRaySafe[i] < d))
			d = gRaySafe[i];
		if ((d <= 0.f) || (d < line * minReach))
			continue;
		const AIFloat3 p = gFrontHome + dir * d;
		if (OnMap(p))
			pts.insertLast(p);
	}
	return pts.length() > 0;
}


// The crossing directly ahead, kept for callers that want a single point.
bool FrontLinePos(AIFloat3& out p)
{
	RebuildFront();
	if (!gFrontValid)
		return false;
	p = gFrontHome + gFrontFwd * FrontFractionAt(gFrontHome);
	return OnMap(p);
}

// On the line, or past it. A tower behind the crossing is defending ground
// nobody is contesting.
bool OnBorder(const AIFloat3& in pos)
{
	RebuildFront();
	if (!gFrontValid || (gRayR.length() == 0))
		return false;
	// Against the ring's radius on THIS position's bearing. The band is a share
	// of that radius rather than a fixed distance, so it means the same thing on
	// a small map and a large one.
	const float band = ai.GetTunable("apex_front_band", FRONT_BAND);
	const int r = RayOf(pos);
	const float here = pos.distance2D(gFrontHome);
	return here >= (gRayR[r] * (1.f - band));
}


// What the enemy's mobile army is WORTH, in metal.
//
// Not mobileThreat: threat and armyCost are different units (a
// threat-vs-metal comparison reads "we are ahead" almost always and any gate
// built on it never fires). GetEnemyCost returns enemyInfos[type].cost, a
// metal sum, directly comparable to armyCost (accumulated from GetCostM).
// Summed over the roles that actually fight.
// Mobile roles only. A building we saw once is still there; a raider is not.
// GetEnemyCostFresh counts only what was seen inside the manager's freshness
// window; the remainder is a ghost, weighted by apex_ghost_weight. At the
// default 1.0 this is arithmetically identical to the raw sum.
float EnemyCostOf(int role)
{
	const float raw = aiEnemyMgr.GetEnemyCost(role);
	float fresh = aiEnemyMgr.GetEnemyCostFresh(role);
	if (fresh > raw)
		fresh = raw;
	// 0.3, was 1.0: measured live (Greenhaven rematch, 2026-08-15) the raw sum
	// read the enemy army at 3x OURS while apexearth watched us dominate --
	// the ghost share was ~2/3 of the total and only ever ratchets up, so
	// every posture gate (massing, attack odds, the killing blow) leaned
	// defensive off units that mostly no longer existed. A mobile unit unseen
	// for the whole freshness window is more likely dead or elsewhere than
	// waiting where we saw it.
	return fresh + (raw - fresh) * ai.GetTunable("apex_ghost_weight", 0.3f);
}

float EnemyArmyCost()
{
	return EnemyCostOf(Unit::Role::ASSAULT.type)
	     + EnemyCostOf(Unit::Role::RAIDER.type)
	     + EnemyCostOf(Unit::Role::RIOT.type)
	     + EnemyCostOf(Unit::Role::SKIRM.type)
	     + EnemyCostOf(Unit::Role::ARTY.type)
	     + EnemyCostOf(Unit::Role::AH.type);
}

// THE SEEN ENEMY LIVES ON THE WATER, so land production cannot reach them --
// build ships, seaplanes or air instead. Two signals, because the role table
// cannot separate a destroyer from a tank (both read RAIDER/ASSAULT): a real
// sub fleet is unambiguous, and otherwise the enemy's centre of mass sitting
// beside water a shipyard could float on is the closest thing script can read
// (no terrain-elevation binding exists; enemyPos is the group centroid from
// the DLL's GetEnemyPos binding). Cached: FindBuildSiteNear is not free and
// this is asked per builder election.
bool gAfloat = false;
int gNextAfloatCheck = 0;
int gNextAfloatLog = 0;

bool EnemyAfloat()
{
	if (aiTerrainMgr.IsWaterAVoid())
		return false;
	if (ai.frame < gNextAfloatCheck)
		return gAfloat;
	gNextAfloatCheck = ai.frame + 10 * SECOND;
	bool now = EnemyCostOf(Unit::Role::SUB.type)
			>= ai.GetTunable("apex_afloat_sub_cost", 400.f);
	if (!now && (aiTerrainMgr.GetLandPercent()
			<= ai.GetTunable("apex_afloat_land_pct", 85.f))) {
		const AIFloat3 at = aiEnemyMgr.GetEnemyPos();
		if (OnMap(at)) {
			CCircuitDef@ sy = Factory::NavalOpening();
			if (sy !is null) {
				const AIFloat3 wet = ai.FindBuildSiteNear(sy, at,
						ai.GetTunable("apex_afloat_near", 900.f));
				now = OnMap(wet);
			}
		}
	}
	if (now != gAfloat || (now && (ai.frame >= gNextAfloatLog))) {
		gNextAfloatLog = ai.frame + 120 * SECOND;
		AiLog(Factory::T() + "apex: enemy afloat=" + (now ? "1" : "0")
			+ " subs=" + int(EnemyCostOf(Unit::Role::SUB.type))
			+ " land%=" + formatFloat(aiTerrainMgr.GetLandPercent(), "", 0, 0));
	}
	gAfloat = now;
	return gAfloat;
}

// THE WHOLE ENEMY ARMY, INCLUDING THE PART THAT DECIDES GAMES.
//
// EnemyArmyCost above sums six roles and counts NEITHER heavy NOR super, so
// dozens of T3 unit defs -- armbanth, corjugg, corkorg, legeheatraymech and the
// rest -- are worth exactly zero to us. A declared push sets IsCommitted, so
// no unit may retreat, and committing while genuinely behind on real standing
// army (T3 invisible to the estimate) is an army that cannot disengage.
//
// Ten defs carry a counted role AND heavy and are double-counted here.
// Over-counting an enemy is the safe error; reading their Korgoths as absent is
// not. Only the two commit decisions read this -- LosingGround and the sizing
// helpers keep the narrower sum, because widening those moves reclaim, rez and
// the front-tower rule as well.
float EnemyFieldCost()
{
	return EnemyArmyCost()
	     + EnemyCostOf(Unit::Role::HEAVY.type)
	     + EnemyCostOf(Unit::Role::SUPER.type);
}

// Behind on the field: they field more army value than we do.
const float BEHIND_RATIO = 1.0f;

// ENEMIES HOLDING GROUND IN OUR OWN BASE, WITHOUT AN INVENTED THRESHOLD.
//
// Builder::BaseUnderAttack asks whether the enemy CENTROID is within 2200 of
// home, and in a team game the centroid of several enemies sits in the middle
// of the map forever, so it never fires except on a 1v1 massed push.
//
// Net influence is ally minus enemy at a point (CInfluenceMap::GetInfluenceAt
// returns influence - INFL_BASE), so its ZERO CROSSING is the question already
// asked in the right units: who owns this ground. No constant to guess at, and
// it is local to our base rather than an average over the whole map.
bool BaseContested()
{
	if (!Builder::gHomeSet)
		return false;
	return ai.GetNetInflAt(Builder::gHomePos) < 0.f;
}

bool LosingGround()
{
	return EnemyArmyCost() > aiMilitaryMgr.armyCost * BEHIND_RATIO;
}

float EnemyArmyFloor()
{
	// A refused query is "unknown", never "no enemies" -- reading a refusal as a
	// meaningful zero is what silently disabled slinging once already.
	const int teams = ai.GetEnemyTeamSize();
	return PORC_THREAT_PER_ENEMY * float((teams > 0) ? teams : 1);
}

// The team front, published by dev_team_income.lua at 78% of the way from our
// own centroid to the enemy's.
// FrontPos is gone with the gadget that fed it: it read ai_frontx_<team>, which
// only ever existed in BAR.sdd. FrontLinePos above answers the same question
// from the influence map, in any game.

}  // namespace Military
