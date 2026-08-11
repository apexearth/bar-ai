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
// Hence: ask once the enemy actually fields an army, and skip while it does not,
// which is the user's "if enemies are really far away then probably not needed
// right away". Sites outside our own footprint bypass that gate; see below for
// why that is a proxy rather than proximity.
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
// apexearth: "if you could almost split the map up into a grid and build
// controlled territories on that grid, then ideally what you try to form is a
// line on the edge of our controlled territory in order to block all enemy
// movement from crossing over into our territory."
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
// A site further from home than the enemy centroid is is not ours to hold -- that
// is an ally's ground on the far side of the map, and a tower we send a builder
// across the map to place is a tower that arrives after the fight.
// Cover the border, do not crowd one bearing.
//
// This ranked our sites purely by distance to aiEnemyMgr.GetEnemyPos() -- a
// SINGLE point, the enemy centroid -- so rank 0 was the site nearest that
// bearing, rank 1 the next nearest, and every tower we ever built marched
// toward the same compass direction. Whichever flank the centroid did not
// point at got nothing, however much of our territory sat on it.
// apexearth, watching: "the AI controls so much on the right because we never
// build any defenses on the right... AI has free right to just walk around our
// defenses", and earlier, with a screenshot: "we do stuff like this and the
// enemy can just go around most of our towers very easily."
//
// Coverage instead: among the sites on our forward edge, take the one that is
// least defended already. gFencePos is the register of every defence we own,
// so "least defended" is a real count and not a guess. Distance to the enemy
// still decides WHICH sites are eligible -- the forward edge is still the
// front -- but among those, the emptiest ground wins.
const float COVER_RADIUS = 900.f;

bool BorderPos(AIFloat3& out p, uint rank)
{
	if (gSitePos.length() == 0)
		return false;
	AIFloat3 e = aiEnemyMgr.GetEnemyPos();
	const float reach = Builder::gHomeSet ? Builder::gHomePos.distance2D(e) : -1.f;

	// The forward edge: the nearest eligible site to the enemy sets the band.
	float edge = -1.f;
	for (uint i = 0; i < gSitePos.length(); ++i) {
		if ((reach > 0.f) && (gSitePos[i].distance2D(Builder::gHomePos) > reach))
			continue;
		const float d = gSitePos[i].distance2D(e);
		if ((edge < 0.f) || (d < edge))
			edge = d;
	}
	if (edge < 0.f)
		return false;

	// COVERAGE, not a wall on one bearing.
	//
	// The first version of this restricted candidates to sites within one band of
	// the forward edge, which fixed WHICH forward site got the tower and left the
	// flanks ineligible -- so the towers still stacked in one place and the enemy
	// still walked around them into the economy. apexearth, with a screenshot:
	// "any idea how to fix our defense placement so AI can stop just walking
	// around them to attack our eco from the back? Happens all the time. You can
	// see we have a ton of defense being built - all concentrated in one spot."
	//
	// Every site we hold is eligible. Score = (defences already near it + 1) x
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
// This measured against BorderPos(edge, 0), and that edge is the closest of OUR
// OWN defence sites to the enemy -- so the definition was self-referential. With
// everything we own sitting at home, home became the border and every rear tower
// passed. Measured from positional telemetry, 12 minutes, +50: our four players
// held 53 defences with 0-17% of them past a quarter of the way to the enemy and
// median positions of -0.22 to 0.14 along the home->enemy axis, i.e. at or
// BEHIND our own base centroid -- and the rear-share check refused none of them,
// because every one read as "on the border".
//
// apexearth, repeatedly and again tonight: "We're making tons of defenses but
// few of them are on the front line. We need to be putting 90% of our defenses
// on the front line."
//
// So it is geometry now: how far along the line from our base to theirs a
// position sits. 0 is our base, 1 is theirs, and anything past FRONT_FRACTION
// counts as forward. GetEnemyPos is the centroid of all enemies, which is a poor
// answer to "where is that one raider" and a perfectly good answer to "which way
// is forward" -- the only thing it is used for here.
const float FRONT_FRACTION = 0.30f;

// WHERE OUR TERRITORY ACTUALLY IS, not where we spawned.
//
// Everything positional measured from Builder::gHomePos, the START position. It
// never moves, so as the base grows forward the origin stays behind it and a
// tower behind the real base still reads as "forward". apexearth, watching:
// "we're basically making tons of defense, but we're making it all, like, behind
// our base" -- true on screen and false to the AI, at the same time, because the
// two were measuring from different places.
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
// apexearth: "We need this to work in a hosted game. Figure out how to do front
// lines properly in a hosted game. This should be easily possible and computable
// based on the current battlefield", then: "You also need to be drawing a line
// across the entire map. So maybe you find the influence zones, and you create a
// curve on the map of a collection of points, and draw that across the edge of
// the map, that is around where your frontline is."
//
// So: not one marker, a CURVE. The influence map is engine-side and always
// present -- GetNetInflAt is ally minus enemy -- so the front is where that
// crosses zero, which is his own definition of it: "where OUR territory ends and
// the ENEMY'S begins". Sampled once per lane across the width of the map, the
// crossings form a line that bulges where they have pushed into us and recedes
// where we have pushed into them.
//
// Nothing here is a gadget. The old source read ai_frontx_<team>, published by
// dev_team_income.lua, which exists only in BAR.sdd -- so in a hosted game it
// returned nothing at all while on the bench it was permissive enough to call a
// tower at -0.17 "near the front". Both wrong, in opposite directions.
//
// Forward is the bearing from our base to the enemy centroid: a poor answer to
// "where is that raider", a fine one to "which way is the enemy", which is all
// it is asked. Lanes run perpendicular to it. Before contact there is no
// crossing and the opening answer is the one the start boxes give -- halfway.
// LANES SPAN THE MAP, they are not a fixed width. 11 lanes at 900 elmos covers
// 9,900 -- fine on Comet Catcher and nowhere near edge to edge on an 8v8 map,
// where the drawn line visibly stopped a third of the way down. apexearth, from
// a screenshot of a hosted game. The count is fixed and the SPACING follows the
// map's diagonal, so the line always reaches both edges whatever it is playing
// on.
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
// apexearth, from a screenshot of his team boxed into the top-left corner of an
// 8v8: "at this point in the game our frontline should appear diagonal just on
// this little edge of the map." The drawn line was four near-vertical strokes
// down the left quarter instead.
//
// Both are correct descriptions of the same model failing. Lanes are laid
// perpendicular to ONE bearing -- our centre to the enemy CENTROID -- so the
// front they describe is always a straight line facing one direction. A team in
// a corner is surrounded across ninety degrees or more, and the average of all
// those enemies points somewhere down the middle, so the lanes end up
// perpendicular to a direction no individual enemy is actually on.
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
// it -- it is our own rear, or the edge of the world.
//
// apexearth, with a screenshot: "Look at this weird circle of turrets purple
// made." Emitting every ray as a build point turns the ring into a literal
// circle of towers around the base, most of them facing nothing. Sampling all
// the way round is still right -- that is what lets a corner read as an arc --
// but only the contested arc of it is the front.
array<bool> gRayHot;

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
			// THE SAFE GROUND CLOSEST TO THE LINE. apexearth: "just pull the line
			// back for where to make defenses."
			//
			// The FURTHEST workable sample, not the first threatened one. Stopping
			// at the first threat was my own assumption -- that a quiet pocket
			// beyond a hot band cannot be walked to -- and it is wrong: the engine
			// tests CanReachAtSafe, which is threat at the DESTINATION plus whether
			// a path exists at all, not a clear straight line. One raider sitting
			// 0.08 out therefore collapsed the whole lane onto the base.
			//
			// THE SAME BAR THE ENGINE USES, not a stricter one. CanReachAtSafe
			// tests `GetBuilderThreatAt(pos) > THREAT_MIN`, and THREAT_MIN is 1.0
			// (util/Defines.h) while the accessor has already subtracted
			// THREAT_BASE. Testing `> 0` instead put the safe edge at 0.00-0.08 in
			// every lane of every game.
			if (ai.GetBuilderThreatAt(p) <= ai.GetTunable("apex_build_threat_bar", 1.f))
				safe = t;
			// EMPTY GROUND IS NOBODY'S, NOT THEIRS. GetNetInflAt is ally minus
			// enemy, so ground neither side has been near reads exactly 0 -- and
			// testing `<= 0` called the first such sample the crossing. Every lane
			// on a flank we simply had not walked into therefore put the front one
			// step from our own base: measured min=0.08 across every 30-second
			// sample of two games, which is the first sample, every time.
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

// One ray per bearing. Each walks outward until the influence turns enemy, and
// records both where that happened and how far out a builder could still work.
void RebuildRing(const AIFloat3& in home)
{
	gRayR.resize(0);
	gRaySafe.resize(0);
	gRayHot.resize(0);
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	const float reach = sqrt(w * w + h * h) * 0.5f;   // half the map diagonal
	const float step = reach / float(FRONT_SAMPLES);
	const float bar = ai.GetTunable("apex_build_threat_bar", 1.f);

	// NOTHING BEHIND US IS FRONT. apexearth: "We know theres no AI with a start
	// point behind us, and theres no room back there for there to be any threat."
	//
	// Firmer than asking the influence map, which answers about this tick: a
	// bearing pointing away from every enemy cannot become the front line because
	// there is nobody back there to make one. Excluding the rear half outright
	// also stops the ring closing on itself, which is what wrapped the drawn line
	// around our own half of the map.
	//
	// apex_front_rear_arc=1 restores the full ring for the case he allowed for --
	// "on some weird maps this may be valid" -- e.g. genuinely surrounded.
	const bool rearToo = ai.GetTunable("apex_front_rear_arc", 0.f) > 0.f;
	AIFloat3 toEnemy = aiEnemyMgr.GetEnemyPos() - home;
	const bool haveBearing = toEnemy.SqLength2D() > NEAR_ZERO;
	if (haveBearing)
		toEnemy.SafeNormalize2D();

	for (int r = 0; r < FRONT_RAYS; ++r) {
		const float ang = 6.2831853f * float(r) / float(FRONT_RAYS);
		const AIFloat3 dir = AIFloat3(cos(ang), 0.f, sin(ang));
		if (!rearToo && haveBearing
			&& ((dir.x * toEnemy.x + dir.z * toEnemy.z) <= 0.f))
		{
			gRayR.insertLast(reach);
			gRaySafe.insertLast(0.f);
			gRayHot.insertLast(false);
			continue;
		}
		float edge = reach;      // never met them: the whole ray is ours
		float safe = 0.f;
		bool hot = false;        // did this bearing find an enemy at all
		for (int i = 1; i <= FRONT_SAMPLES; ++i) {
			const float d = step * float(i);
			const AIFloat3 p = home + dir * d;
			if (!OnMap(p)) {
				if (edge > d)
					edge = d;    // the map edge is a front we never have to hold
				break;
			}
			if (ai.GetBuilderThreatAt(p) <= bar)
				safe = d;
			const float inf = ai.GetNetInflAt(p);
			if (inf < 0.f) {
				edge = d;
				hot = true;
				break;
			}
		}
		gRayR.insertLast(edge);
		gRaySafe.insertLast(safe);
		gRayHot.insertLast(hot);
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
// NOT a list of places to build -- conflating the two is why the drawn line came
// out "super tiny and weird" (apexearth): it was showing the build spots, which
// clamp to the safe edge and drop most bearings, so what appeared on screen was
// a few stubs near the base rather than the front.
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
// apexearth: "we need no 'gaps' there. So a line of turrets are needed, all
// within range of each other's firing radius, so no 'leaks' can get through."
//
// That is a definite objective, and it is the first one this AI has had for
// defence: sample the arc at intervals of the turret's OWN weapon range, so a
// raider cannot pass between two of them. The spacing is read from the def via
// GetMaxRange rather than guessed -- the old FRONT_FENCE_SPREAD was a flat 700
// for an armllt that reaches 430 and a Rattlesnake that reaches much further,
// which leaves a hole in one case and wastes metal in the other.
//
// Sampling the ARC rather than the bearings is the point: 24 fixed bearings put
// points 785 elmos apart at radius 3000 and 130 apart at radius 500, so the same
// ring is full of holes far out and stacked up close. Arc length is the honest
// unit for "no gaps".
bool FrontLineSpots(array<AIFloat3>& out pts, float spacing)
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

		// How many turrets this segment of arc needs to be gap-free.
		const float arc = step * ((d0 + d1) * 0.5f);
		int n = int(arc / spacing);
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
// Not mobileThreat: UpdateMassing's own comment already warns that threat and
// armyCost are different units, and it is right -- observed army=10727 against
// enemyThr=296, so a threat-vs-metal comparison reads "we are ahead" almost
// always and any gate built on it never fires. GetEnemyCost returns
// enemyInfos[type].cost, a metal sum, which is directly comparable to armyCost
// (accumulated from GetCostM). Summed over the roles that actually fight.
float EnemyArmyCost()
{
	return aiEnemyMgr.GetEnemyCost(Unit::Role::ASSAULT.type)
	     + aiEnemyMgr.GetEnemyCost(Unit::Role::RAIDER.type)
	     + aiEnemyMgr.GetEnemyCost(Unit::Role::RIOT.type)
	     + aiEnemyMgr.GetEnemyCost(Unit::Role::SKIRM.type)
	     + aiEnemyMgr.GetEnemyCost(Unit::Role::ARTY.type)
	     + aiEnemyMgr.GetEnemyCost(Unit::Role::AH.type);
}

// Behind on the field: they field more army value than we do.
const float BEHIND_RATIO = 1.0f;

// ENEMIES HOLDING GROUND IN OUR OWN BASE, WITHOUT AN INVENTED THRESHOLD.
//
// Builder::BaseUnderAttack asks whether the enemy CENTROID is within 2200 of
// home, and in a 4v4 the centroid of eight enemies sits in the middle of the map
// forever: measured 0 firings across three 16-minute games. It catches a massed
// push on a 1v1 and nothing else.
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
