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

float ForwardFraction(const AIFloat3& in pos)
{
	if (!Builder::gHomeSet)
		return 0.f;
	const AIFloat3 home = Builder::gHomePos;
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
const int   FRONT_LANES    = 5;       // each side of centre, so 11 lanes
const float FRONT_LANE_GAP = 900.f;   // elmos between lanes
const int   FRONT_SAMPLES  = 14;
const float FRONT_SCAN_END = 1.15f;   // a little past their centroid
const float FRONT_BAND     = 0.18f;   // how wide "on the line" is, as a fraction
const float FRONT_SETBACK  = 0.12f;   // build this far inside it, not on it

// Per lane: the fraction along home->enemy at which that lane's influence
// crosses. Index 0 is the leftmost lane.
array<float> gFrontLane;
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

	if (!Builder::gHomeSet)
		return;
	const AIFloat3 home = Builder::gHomePos;
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
		const AIFloat3 origin = home + side * (float(lane) * FRONT_LANE_GAP);
		float found = -1.f;
		for (int i = 1; i <= FRONT_SAMPLES; ++i) {
			const float t = FRONT_SCAN_END * float(i) / float(FRONT_SAMPLES);
			const AIFloat3 p = origin + fwd * t;
			if (!OnMap(p))
				break;
			// The crossing: ground where they out-hold us.
			if (ai.GetNetInflAt(p) <= 0.f) {
				found = t;
				break;
			}
		}
		// A lane with no crossing is one we hold all the way, or one nobody has
		// contested. Halfway is the start-box answer and is right for both.
		gFrontLane.insertLast((found < 0.f) ? 0.5f : found);
	}
	gFrontValid = true;
}

// Which lane a position falls in, and how far along the axis it sits.
int LaneOf(const AIFloat3& in pos)
{
	const AIFloat3 d = pos - gFrontHome;
	const float off = d.x * gFrontSide.x + d.z * gFrontSide.z;
	int lane = int(off / FRONT_LANE_GAP + (off >= 0.f ? 0.5f : -0.5f));
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
bool FrontCurve(array<AIFloat3>& out pts)
{
	RebuildFront();
	pts.resize(0);
	if (!gFrontValid)
		return false;
	// PULLED BACK OFF THE LINE, ON PURPOSE. apexearth: "Never send a constructor
	// to build a tower in a dangerous place... what is the point in trying to
	// make a tower that can never be built? ... Build behind the line, not on
	// it." The crossing IS contested ground by definition, so a builder sent
	// exactly there is refused by its own safety veto and the order dies: 14
	// orders produced no towers. These points sit just inside our side of it,
	// which is where a tower can be finished and still cover the line.
	const float back = ai.GetTunable("apex_front_setback", FRONT_SETBACK);
	for (uint i = 0; i < gFrontLane.length(); ++i) {
		const float laneOff = (float(i) - float(FRONT_LANES)) * FRONT_LANE_GAP;
		float t = gFrontLane[i] - back;
		if (t < 0.f)
			t = 0.f;
		pts.insertLast(gFrontHome + gFrontSide * laneOff + gFrontFwd * t);
	}
	return true;
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
	const float band = ai.GetTunable("apex_front_band", FRONT_BAND);
	// Against the crossing in THIS position's lane, not against one global
	// number -- which is the point of computing a curve. A tower on a flank the
	// enemy has pushed into is on the line even though the centre has not moved.
	return ForwardFraction(pos) >= (FrontFractionAt(pos) - band);
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
