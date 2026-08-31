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

// The high-water home->enemy separation, decayed on a long half-life. See
// ForwardFraction: this is the denominator, and it must not shrink just because
// the enemy walked in.
float gFwdSpan = 0.f;
int gFwdSpanAt = 0;

// WHERE A POINT SITS ON THE HOME->ENEMY AXIS, 0 at us and 1 at them.
//
// Read as a stable map coordinate by recall, the defend leash, site safety and
// the build-site ordering, so it has to mean the same thing from minute 5 to
// minute 40. Taken from aiEnemyMgr.GetEnemyPos() -- the LIVE centroid of every
// enemy we can see -- it did not: enemies standing in our base drag that
// centroid most of the way home, which both turns the axis around and collapses
// the denominator, so a unit a quarter of the way out reads as deep in their
// territory exactly when they are pushing into us. Recall and the leash then
// fire on the whole army at once, and the further in they get the further back
// our own recall line moves.
//
// Direction comes from the REMEMBERED enemy centre instead, and the denominator
// from the deepest separation we have seen, so an incursion cannot move either.
float ForwardFraction(const AIFloat3& in pos)
{
	if (!Builder::gHomeSet)
		return 0.f;
	const bool stable = ai.GetTunable("apex_fwd_stable", TUNE_FWD_STABLE) > 0.f;
	const AIFloat3 home = TerritoryCentre();
	AIFloat3 e;
	if (!stable || !Front::FoeMid(e))
		e = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(e))
		return 0.f;
	const float dx = e.x - home.x;
	const float dz = e.z - home.z;
	const float sq = dx * dx + dz * dz;
	if (sq < NEAR_ZERO)
		return 0.f;
	const float span = sqrt(sq);
	float ref = span;
	if (stable) {
		// Decayed by frame, not by call: this is read from a dozen places and
		// several times an update, so a per-call decay would run at a rate set
		// by how often other code happened to ask.
		const float hl = ai.GetTunable("apex_fwd_span_halflife", TUNE_FWD_SPAN_HALFLIFE);
		const int dt = ai.frame - gFwdSpanAt;
		if ((hl > 0.f) && (dt > 0))
			gFwdSpan *= pow(0.5f, (float(dt) / float(SECOND)) / hl);
		gFwdSpanAt = ai.frame;
		if (span > gFwdSpan)
			gFwdSpan = span;
		ref = gFwdSpan;
	}
	return ((pos.x - home.x) * dx + (pos.z - home.z) * dz) / (span * ref);
}

}  // namespace Military
