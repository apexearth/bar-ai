namespace Front {

// Where our territory ends and the enemy's is about to begin.
//
// Four definitions died against measurement, in this order:
//   1. Cells where BOTH sides are present. One Jade 8v8 scan: 339 ally cells,
//      56 enemy cells, ZERO holding both. Where one side is strong the other
//      reads ~0, so the fields are disjoint and the test only fires where both
//      are too faint to mean anything.
//   2. The boundary between the two fields. Found 2-3 cells. Enemy influence
//      counts only KNOWN enemy units and is far too sparse to draw a line with.
//   3. The edge of our influence at a 15%-of-peak bar. That bar picks out the
//      dense CORE of our territory, so its edge sat BEHIND our own army and was
//      full of gaps.
//   4. That same ring, undirected. Half of any ring faces our own rear, which
//      is a danger zone but is not a front line.
//
// So: territory is a LOW bar (anything we meaningfully hold), its perimeter
// wraps the whole territory, and the ring is then split by direction -- the part
// facing the enemy is the FRONT, the part facing our own fog is the BACK.
// Before we have seen any enemy there is no direction to split on, and the
// front is honestly UNKNOWN rather than guessed.

const float MIN_WIDTH = 80.f;
const float MAX_WIDTH = 2000.f;

// Territory is everything we meaningfully hold, not only where we are massed.
// At 15% of peak this picked out the core alone and the ring sat behind our own
// army. Ally influence peaks ~520, so 3% is ~15 -- clear of numerical noise, but
// it includes the thin edges we really do hold.
const float TERRITORY_FLOOR = 1.0f;
const float TERRITORY_FRAC = 0.03f;
// Enemy influence is on another scale entirely -- it counts only what we have
// SEEN, and peaks under 33 against ally's 520 -- so it gets its own bar. An
// absolute floor of 5 once erased it completely and every AI read cFoe=0 for a
// whole game, which made the front vanish instead of move.
const float FOE_FLOOR = 1.0f;
const float FOE_FRAC = 0.10f;

const float CHOKE_NEAR = 600.f;
// How much further than the closest front cell a cell may sit and still count
// as front. Beyond this it is enemy-facing flank, not the line.
//
// This was a flat 3,000 elmos, and an absolute distance cannot mean the same
// thing on two maps. Model the perimeter as a ring of radius R about our
// centroid with the enemy at distance D: the closest cell sits at D - R, and a
// cell at bearing theta off the axis to them at sqrt(D^2 - 2DR cos(theta) + R^2),
// so keeping everything within (closest + band) keeps the arc
// |theta| <= acos(1 - band/R). band = R keeps the enemy-facing half, band = R/2
// keeps +/-60 degrees. That angle depends on band/R and NOT on D, which is why
// the band belongs in units of our own territory radius: a fraction of the
// home-to-enemy separation would mean a different arc every time either side's
// holdings changed.
//
// R is measured from the perimeter this same scan just built, so nothing about
// it is assumed. FRONT_BAND_FRAC is the one policy number left: how wide a front
// one player holds, as a share of its own territory radius.
const float FRONT_BAND_FRAC = 1.0f;
const int RECLASSIFY = 10 * SECOND;
const int SEAM_N = 40;

// Blackboard keys for pooling the enemy bearing across the team.
const string TV_FOE_X = "apexFoeX";
const string TV_FOE_Z = "apexFoeZ";
const string TV_FOE_W = "apexFoeW";
// And for splitting the line into per-player sectors: each AI publishes where it
// lives, and a front cell belongs to whichever ally is nearest it.
const string TV_HOME_X = "apexHomeX";
const string TV_HOME_Z = "apexHomeZ";

enum Owner { EMPTY = 0, OURS = 1, CONTESTED = 2, THEIRS = 3 };
enum Edge { NONE = 0, FRONT = 1, BACK = 2 };

array<int> gIdx;
array<int> gOwner;
int gNextClassify = 0;
bool gGathered = false;

array<AIFloat3> gPerim;    // the whole ring around our territory
array<int> gEdge;          // parallel to gPerim: FRONT, BACK or NONE
array<bool> gMine;         // parallel to gPerim: this cell is THIS AI's to hold
array<float> gMateX;       // ally home positions, refreshed each Scan
array<float> gMateZ;
bool gSectored = false;    // false until at least one ally home is published
array<AIFloat3> gPrevDraw; // what we drew last pass, so it can be erased
array<float> gFoeSeen;     // persistent memory of where enemies have been
bool gFoeKnown = false;
AIFloat3 gOurMid;
AIFloat3 gFoeMid;
float gPresAlly = TERRITORY_FLOOR;
float gPresFoe = FOE_FLOOR;
int gDbgAlly = 0;
int gDbgFoe = 0;
bool gDrawn = false;
bool gChokeDrawn = false;

void Gather()
{
	if (gGathered)
		return;
	gGathered = true;
	gFoeSeen.resize(SEAM_N * SEAM_N);
	for (uint k = 0; k < gFoeSeen.length(); ++k)
		gFoeSeen[k] = 0.f;
	const int n = ai.GetChokePointCount();
	for (int i = 0; i < n; ++i) {
		const float w = ai.GetChokePointWidth(i);
		if ((w < MIN_WIDTH) || (w > MAX_WIDTH))
			continue;
		gIdx.insertLast(i);
		gOwner.insertLast(EMPTY);
	}
	AiLog("apex: frontline gathered " + gIdx.length() + "/" + n + " usable chokepoints");
}

AIFloat3 GridPos(int i, int j)
{
	AIFloat3 p;
	p.x = float(AiTerrainWidth()) * (float(i) + .5f) / float(SEAM_N);
	p.z = float(AiTerrainHeight()) * (float(j) + .5f) / float(SEAM_N);
	return p;
}

int Classify(const AIFloat3& in pos)
{
	const float ally = ai.GetAllyInflAt(pos);
	const float foe = ai.GetEnemyInflAt(pos);
	if ((ally < gPresAlly) && (foe < gPresFoe))
		return EMPTY;
	if (ally > foe * 2.f)
		return OURS;
	if (foe > ally * 2.f)
		return THEIRS;
	return CONTESTED;
}

// SECTORS: which part of the team's line is THIS AI's to hold.
//
// Territory is measured from ally-wide influence, so every AI on the team
// computes the same perimeter and the same enemy bearing -- and then all of them
// anchored on the same few cells, because the trim below keeps only the arc
// nearest the enemy and that arc belongs to whichever ally happens to sit
// furthest forward. apexearth: "I routinely see our units patrolling behind our
// own allies bases. meanwhile, the enemy is attacking one of our frontline bases
// and our huge army isn't there to protect it."
//
// Same failure the defence placement had (territory.as: ranking every site by
// distance to ONE enemy point sent every tower down one bearing), one level up:
// a single closest-approach test cannot describe a line held by eight players.
//
// A cell belongs to the ally whose home is nearest it -- a Voronoi split of the
// line over the team, which is how a human team divides a front. It needs the
// allies' home positions, and nothing enumerates them, so they are pooled the
// same way the enemy bearing already is.
void ReadMates()
{
	gMateX.resize(0);
	gMateZ.resize(0);
	if (Builder::gHomeSet) {
		ai.PublishTeamValue(TV_HOME_X, Builder::gHomePos.x);
		ai.PublishTeamValue(TV_HOME_Z, Builder::gHomePos.z);
	}
	array<Id>@ mates = ai.GetTeamIds();
	for (uint i = 0; (mates !is null) && (i < mates.length()); ++i) {
		const int id = int(mates[i]);
		if (id == ai.teamId)
			continue;   // ours is gHomePos; a mate entry for it would be a tie
		const float x = ai.ReadTeamValue(id, TV_HOME_X, -1.f);
		const float z = ai.ReadTeamValue(id, TV_HOME_Z, -1.f);
		if ((x < 0.f) || (z < 0.f))
			continue;
		gMateX.insertLast(x);
		gMateZ.insertLast(z);
	}
	// No mate has published yet, or we have no home of our own to compare
	// against: the whole line is ours, which is the pre-sector behaviour and the
	// right answer in a 1v1.
	gSectored = Builder::gHomeSet && (gMateX.length() > 0);
}

bool Mine(const AIFloat3& in p)
{
	if (!gSectored)
		return true;
	const float own = p.distance2D(Builder::gHomePos);
	for (uint i = 0; i < gMateX.length(); ++i) {
		const float dx = p.x - gMateX[i];
		const float dz = p.z - gMateZ[i];
		if (sqrt(dx * dx + dz * dz) < own)
			return false;
	}
	return true;
}

// The radius of what we hold: mean distance from our centroid to the perimeter
// this scan found. Declared after gPerim/gOurMid because a global read above its
// own declaration is a `No matching symbol` that disables the whole variant.
float TerritoryRadius()
{
	if (gPerim.length() == 0)
		return 0.f;
	float sum = 0.f;
	for (uint k = 0; k < gPerim.length(); ++k)
		sum += gPerim[k].distance2D(gOurMid);
	return sum / float(gPerim.length());
}

float FrontBand()
{
	float b = TerritoryRadius()
			* ai.GetTunable("apex_front_band_frac", FRONT_BAND_FRAC);
	// A band under the grid's own resolution cannot mean anything: the perimeter
	// is quantised at one cell, so one cell diagonal is the floor.
	const float cw = float(AiTerrainWidth()) / float(SEAM_N);
	const float ch = float(AiTerrainHeight()) / float(SEAM_N);
	const float least = sqrt(cw * cw + ch * ch);
	return (b < least) ? least : b;
}

void Scan()
{
	gPerim.resize(0);
	gEdge.resize(0);
	gMine.resize(0);
	gDbgAlly = 0;
	gDbgFoe = 0;
	ReadMates();

	float maxAlly = 0.f, maxFoe = 0.f;
	for (int i = 0; i < SEAM_N; ++i) {
		for (int j = 0; j < SEAM_N; ++j) {
			const AIFloat3 p = GridPos(i, j);
			const float a = ai.GetAllyInflAt(p);
			const float f = ai.GetEnemyInflAt(p);
			if (a > maxAlly) maxAlly = a;
			if (f > maxFoe) maxFoe = f;
		}
	}
	gPresAlly = maxAlly * TERRITORY_FRAC;
	if (gPresAlly < TERRITORY_FLOOR) gPresAlly = TERRITORY_FLOOR;
	gPresFoe = maxFoe * FOE_FRAC;
	if (gPresFoe < FOE_FLOOR) gPresFoe = FOE_FLOOR;

	array<bool> ours(SEAM_N * SEAM_N);
	float ox = 0.f, oz = 0.f, ow = 0.f;
	float fx = 0.f, fz = 0.f, fw = 0.f;
	for (int i = 0; i < SEAM_N; ++i) {
		for (int j = 0; j < SEAM_N; ++j) {
			const int me = i * SEAM_N + j;
			const AIFloat3 p = GridPos(i, j);
			// Territory is where we are ON TOP, not merely where we are present.
			// Ally influence counts MOBILE units, so an army pushing into enemy
			// ground painted that ground as ours, the perimeter followed the army
			// instead of our holdings, and the front got drawn deep inside enemy
			// territory -- apexearth: "i see the front lines are often drawn where
			// it's full of enemies. How are we supposed to hold or make defense on
			// any sort of front line when it's in any territory?" Every tower
			// request there then died to the danger veto: 202 requests, 8,360
			// metal of defence actually built.
			const float av = ai.GetAllyInflAt(p);
			const float fv = ai.GetEnemyInflAt(p);
			const bool a = (av >= gPresAlly) && (av > fv);
			ours[me] = a;
			if (a) {
				++gDbgAlly;
				ox += p.x; oz += p.z; ow += 1.f;
			}
			// Enemy sightings are REMEMBERED, not sampled. A raid that passes
			// through is gone from the influence map seconds later, but the fact
			// that their territory lies that way does not stop being true.
			if (fv >= gPresFoe) {
				++gDbgFoe;
				gFoeSeen[me] += 1.f;
			} else {
				gFoeSeen[me] *= 0.995f;
			}
			if (gFoeSeen[me] > 0.5f) {
				fx += p.x * gFoeSeen[me];
				fz += p.z * gFoeSeen[me];
				fw += gFoeSeen[me];
			}
		}
	}
	if (ow > 0.f) {
		gOurMid.x = ox / ow;
		gOurMid.z = oz / ow;
	}
	// Share the enemy bearing across the team.
	//
	// Each AI's influence map holds only what THAT AI knows, and rear players
	// never see anyone -- measured at 248 of 400 samples reading cFoe=0 in one
	// Jade 8v8. Alone, those players conclude there is no front and place
	// nothing, and if the drawing AI happens to be one of them the overlay is
	// empty all game. The sighting a forward teammate has is just as true for
	// everyone behind them, so it is pooled.
	if (fw > 0.f) {
		ai.PublishTeamValue(TV_FOE_X, fx / fw);
		ai.PublishTeamValue(TV_FOE_Z, fz / fw);
		ai.PublishTeamValue(TV_FOE_W, fw);
	}
	float tx = 0.f, tz = 0.f, tw = 0.f;
	array<Id>@ mates = ai.GetTeamIds();
	for (uint i = 0; (mates !is null) && (i < mates.length()); ++i) {
		const int id = int(mates[i]);
		const float w = ai.ReadTeamValue(id, TV_FOE_W, 0.f);
		if (w <= 0.f)
			continue;
		tx += ai.ReadTeamValue(id, TV_FOE_X, 0.f) * w;
		tz += ai.ReadTeamValue(id, TV_FOE_Z, 0.f) * w;
		tw += w;
	}
	gFoeKnown = (tw > 0.f);
	if (gFoeKnown) {
		gFoeMid.x = tx / tw;
		gFoeMid.z = tz / tw;
	}

	for (int i = 0; i < SEAM_N; ++i) {
		for (int j = 0; j < SEAM_N; ++j) {
			const int me = i * SEAM_N + j;
			if (!ours[me])
				continue;
			bool edge = false;
			for (int di = -1; (di <= 1) && !edge; ++di) {
				for (int dj = -1; (dj <= 1) && !edge; ++dj) {
					const int ni = i + di;
					const int nj = j + dj;
					if ((ni < 0) || (nj < 0) || (ni >= SEAM_N) || (nj >= SEAM_N))
						continue;   // the map edge is not a front
					if (!ours[ni * SEAM_N + nj])
						edge = true;
				}
			}
			if (!edge)
				continue;
			const AIFloat3 p = GridPos(i, j);
			gPerim.insertLast(p);
			const bool mine = Mine(p);
			gMine.insertLast(mine);
			if (!gFoeKnown) {
				gEdge.insertLast(NONE);
				continue;
			}
			// Facing them is necessary but not sufficient. The far flank of a
			// large territory faces the enemy too and is nowhere near them;
			// apexearth: "should prefer frontlines near enemies". So the front
			// is the enemy-facing arc that is also within a band of the closest
			// approach to their territory.
			//
			// Measured from OUR OWN home for the cells that are ours, not from the
			// team centroid. That centroid is the same point for every AI on the
			// team, so a player sitting on a flank had its entire border projecting
			// backwards along the team bearing and classified as back line -- it
			// had no front of its own, and its army anchored on somebody else's.
			const float rx = (mine && Builder::gHomeSet) ? Builder::gHomePos.x : gOurMid.x;
			const float rz = (mine && Builder::gHomeSet) ? Builder::gHomePos.z : gOurMid.z;
			const float facing = (p.x - rx) * (gFoeMid.x - rx)
					+ (p.z - rz) * (gFoeMid.z - rz);
			if (facing <= 0.f) {
				gEdge.insertLast(BACK);
				continue;
			}
			gEdge.insertLast(FRONT);
		}
	}

	// Trim the enemy-facing arc down to the part actually near them. On a large
	// territory the far flank faces the enemy too and is nowhere near the
	// fighting; keeping it made the line span our whole border.
	// Trimmed PER SECTOR. One closest-approach figure for the whole team keeps
	// only the arc in front of whichever ally stands furthest forward, and demotes
	// every other player's frontage to back line -- which is how eight AIs came to
	// share one anchor behind one ally's base.
	if (!gFoeKnown)
		return;
	float closeMine = -1.f;
	float closeTeam = -1.f;
	for (uint k = 0; k < gPerim.length(); ++k) {
		if (gEdge[k] != FRONT)
			continue;
		const float d = gPerim[k].distance2D(gFoeMid);
		if ((closeTeam < 0.f) || (d < closeTeam))
			closeTeam = d;
		if (gMine[k] && ((closeMine < 0.f) || (d < closeMine)))
			closeMine = d;
	}
	const float band = FrontBand();
	for (uint k = 0; k < gPerim.length(); ++k) {
		if (gEdge[k] != FRONT)
			continue;
		const float ref = (gMine[k] && (closeMine >= 0.f)) ? closeMine : closeTeam;
		if (gPerim[k].distance2D(gFoeMid) > ref + band)
			gEdge[k] = BACK;
	}
}

// Mean projection of an edge kind onto the direction from our territory centroid
// toward the enemy, in elmos. FRONT must come out positive and BACK negative.
//
// Measured against each AI's own BASE first, which was confounded: the perimeter
// is ally-WIDE, so a player sitting on the enemy-facing corner has the team's
// far back edge further from it than the front is, and the comparison came out
// a coin flip (228 vs 237) while the geometry was actually fine.
float MeanDist(int kind)
{
	const float dx = gFoeMid.x - gOurMid.x;
	const float dz = gFoeMid.z - gOurMid.z;
	const float len = sqrt(dx * dx + dz * dz);
	if (len < 1.f)
		return 0.f;
	float sum = 0.f;
	uint n = 0;
	for (uint k = 0; k < gEdge.length(); ++k) {
		if (gEdge[k] != kind)
			continue;
		sum += ((gPerim[k].x - gOurMid.x) * dx + (gPerim[k].z - gOurMid.z) * dz) / len;
		++n;
	}
	return (n == 0) ? 0.f : (sum / float(n));
}

uint CountEdge(int kind)
{
	uint n = 0;
	for (uint k = 0; k < gEdge.length(); ++k) {
		if (gEdge[k] == kind)
			++n;
	}
	return n;
}

uint CountOf(int owner)
{
	uint n = 0;
	for (uint k = 0; k < gOwner.length(); ++k) {
		if (gOwner[k] == owner)
			++n;
	}
	return n;
}

void Update()
{
	Gather();
	DrawFrontLine();
	PumpDraw();   // every tick, not every rescan -- see DRAW_PER_TICK
	if (ai.frame < gNextClassify)
		return;
	gNextClassify = ai.frame + RECLASSIFY;

	Scan();
	for (uint k = 0; k < gIdx.length(); ++k)
		gOwner[k] = Classify(ai.GetChokePointPos(gIdx[k]));

	AiLog("apex: frontline perim=" + gPerim.length()
			+ " front=" + CountEdge(FRONT) + " back=" + CountEdge(BACK)
			+ " mine=" + MineEdge(FRONT) + " sectors=" + (gSectored ? int(gMateX.length()) + 1 : 1)
			+ " foeKnown=" + (gFoeKnown ? 1 : 0)
			+ " cAlly=" + gDbgAlly + " cFoe=" + gDbgFoe
			+ " bar=" + int(gPresAlly) + "/" + int(gPresFoe)
			+ " R=" + int(TerritoryRadius()) + " band=" + int(FrontBand())
			+ " ourMid=" + int(gOurMid.x) + "," + int(gOurMid.z)
			+ " foeMid=" + int(gFoeMid.x) + "," + int(gFoeMid.z)
			+ " lane=" + int(aiSetupMgr.GetLanePos().x) + "," + int(aiSetupMgr.GetLanePos().z)
			+ " frontD=" + int(MeanDist(FRONT)) + " backD=" + int(MeanDist(BACK)));

	// frontPos is published by Posture::UpdateLanePos, which vets the point for
	// direction, on-map and stickiness. This function ran more often and with none
	// of those checks, so whichever it wrote last is what the army got.

	Draw();
}

// Where the front should be before anyone has seen anything, from start-box
// geometry alone. apexearth: "do we know the centerpoint of our startbox
// compared to centerpoint of enemy start box? divide the map in half based on
// the angles and midpoint there and bam you have around where the frontline
// should be."
//
// The engine already derives exactly this: CSetupManager spreads the allies
// along a line taken from the start-box geometry and hands each AI its own slot
// as lanePos, so it is a per-player share of that midline rather than one point
// the whole team crowds. Now bound to script.
bool LaneFront(AIFloat3& out spot)
{
	const AIFloat3 lane = aiSetupMgr.GetLanePos();
	if (!ai.IsPosOnMap(lane))
		return false;
	spot = lane;
	return true;
}

// Nearest point on the front to `from`. Falls back to the start-box lane while
// no enemy has been seen, so the opening has a sensible prior instead of
// nothing.
// OUR SECTOR FIRST. Nearest-front-cell over the whole team line is what put the
// anchor behind an ally: their frontage is genuinely nearer to us than our own
// once the trim has demoted ours. Only if we own no front cell at all -- a rear
// player with nothing of its own on the line -- does the team line answer.
bool FrontNear(const AIFloat3& in from, AIFloat3& out spot)
{
	if (!gFoeKnown)
		return LaneFront(spot);
	for (int pass = 0; pass < 2; ++pass) {
		float best = -1.f;
		for (uint k = 0; k < gPerim.length(); ++k) {
			if (gEdge[k] != FRONT)
				continue;
			if ((pass == 0) && !gMine[k])
				continue;
			const float d = gPerim[k].distance2D(from);
			if ((best < 0.f) || (d < best)) {
				best = d;
				spot = gPerim[k];
			}
		}
		if (best >= 0.f)
			return true;
	}
	return false;
}

// A front cell that also sits in a corridor: the best metal-per-tower there is.
bool FrontChoke(const AIFloat3& in from, AIFloat3& out spot)
{
	float best = -1.f;
	for (uint k = 0; k < gPerim.length(); ++k) {
		if ((gEdge[k] != FRONT) || !gMine[k])
			continue;   // an ally's corridor is an ally's to hold
		for (uint c = 0; c < gIdx.length(); ++c) {
			const AIFloat3 cp = ai.GetChokePointPos(gIdx[c]);
			if (cp.distance2D(gPerim[k]) > CHOKE_NEAR)
				continue;
			const float d = cp.distance2D(from);
			if ((best < 0.f) || (d < best)) {
				best = d;
				spot = cp;
			}
		}
	}
	return best >= 0.f;
}

uint MineEdge(int kind)
{
	uint n = 0;
	for (uint k = 0; k < gEdge.length(); ++k) {
		if ((gEdge[k] == kind) && gMine[k])
			++n;
	}
	return n;
}

uint FrontSize() { return CountEdge(FRONT); }
bool IsFrontKnown() { return gFoeKnown; }

// ---------------------------------------------------------------------------
// Debug overlay. Map LINES, not points. A point is a PING -- it fires an alert
// and a minimap flash -- which at this density is unreadable. Lines just draw.
// Allies and spectators see these. Off for anything but a watched game.
const bool DRAW = false;  // ON draws real map markers -- allies see them

// The server DROPS map-draw commands once 25 arrive with under 50ms between
// each -- GameServer.cpp, NETMSG_MAPDRAW:
//
//     mapDrawTimings[a].second > 25  ->  break
//
// It is anti-DOS, it is silent, and it comments that the rate "is impossible to
// reach manually, but (very) easily through Lua". An AI hits it just as easily:
// ~80 front segments plus ~78 chokepoint segments went out in one burst every
// 10 seconds, so the first 25 drew and the rest vanished with no error anywhere.
// That is the whole mystery of the missing overlay, and of the chokepoint layer
// being "missing a bunch of where these should be".
//
// So drawing is queued and metered: a small batch per tick, with the tick gap
// resetting the server's consecutive-command counter.
// Sized against the server's 25-in-a-row/50ms drop rule. AiUpdate runs every 30
// frames, which is 1 game second -- but the server's window is REAL time, so at
// speed 20 that tick gap is only ~50ms and consecutive ticks can start sharing
// one window. A smaller batch keeps the running count clear of 25 even then.
const uint DRAW_PER_TICK = 8;
array<AIFloat3> gQueueA;
array<AIFloat3> gQueueB;   // == A means erase-at-A rather than line A->B

void Enqueue(const AIFloat3& in a, const AIFloat3& in b)
{
	gQueueA.insertLast(a);
	gQueueB.insertLast(b);
}

void PumpDraw()
{
	uint sent = 0;
	while ((gQueueA.length() > 0) && (sent < DRAW_PER_TICK)) {
		if (gQueueA[0] == gQueueB[0])
			ai.DrawErase(gQueueA[0]);
		else
			ai.DrawLine(gQueueA[0], gQueueB[0]);
		gQueueA.removeAt(0);
		gQueueB.removeAt(0);
		++sent;
	}
}

// THE COMPUTED FRONT, ON SCREEN. apexearth: "If you think it's helpful, you can
// draw the perceived front line on the screen for me to see."
//
// It is helpful: every disagreement tonight between what he sees and what the
// telemetry says has come from the AI and the human measuring from different
// places. Drawing what the AI believes settles that by eye in seconds.
//
// Segments between consecutive points of Military::FrontCurve -- the influence
// crossing, lane by lane. Redrawn on a slow cadence because the server drops
// map-draw commands after 25 in a row inside 50ms and BAR's own widget erases
// every mark after 60 seconds, so this repaints inside that window rather than
// accumulating.
int gNextFrontDraw = 0;
array<AIFloat3> gFrontDrawn;

void DrawFrontLine()
{
	if (ai.GetTunable("apex_draw_front", 1.f) <= 0.f)
		return;
	if (ai.frame < gNextFrontDraw)
		return;
	gNextFrontDraw = ai.frame + 20 * SECOND;

	for (uint i = 0; i < gFrontDrawn.length(); ++i)
		Enqueue(gFrontDrawn[i], gFrontDrawn[i]);   // erase the last one
	gFrontDrawn.resize(0);

	array<AIFloat3> line;
	if (!Military::FrontCurve(line) || (line.length() < 2))
		return;
	// THE LINE ENDS WHERE IT RUNS OUT, IT DOES NOT WRAP ROUND THE BACK.
	//
	// apexearth: "You saw how the frontline now wraps around our half of the map?
	// ... essentially if the frontline hits the edge of the map we should stop
	// there."
	//
	// FrontCurve emits only the contested bearings, so the arc has gaps in it
	// wherever a ray met nobody or walked off the map. Joining every consecutive
	// pair then draws a chord straight across our own half between the two ends of
	// the arc, which is the wrap he is describing -- a drawing artefact on top of
	// a curve that is already correct.
	//
	// Neighbouring bearings sit one ring-step apart; anything much wider than that
	// is not a neighbour, it is the gap. Break the polyline there.
	const float step = 6.2831853f / float(Military::FRONT_RAYS);
	for (uint i = 1; i < line.length(); ++i) {
		if (!OnMap(line[i - 1]) || !OnMap(line[i]))
			continue;
		const float r = line[i].distance2D(Military::gFrontHome);
		if (line[i - 1].distance2D(line[i]) > (r * step * 2.5f))
			continue;   // the arc ended here
		Enqueue(line[i - 1], line[i]);
		gFrontDrawn.insertLast(line[i - 1]);
	}
}

void Draw()
{
	if (!DRAW)
		return;

	// ONE AI draws. Ally influence is ally-WIDE, so all eight compute virtually
	// the same perimeter -- and DeletePointsAndLines erases other players' marks
	// at that position too, so they spent the game erasing each other's lines.
	// That is why the overlay faded out mid-game.
	if (ai.teamId != Factory::ElectorTeamId())
		return;

	// A rescan replaces the queue outright; a backlog of stale segments is worse
	// than a gap, and the 60s auto-eraser cleans up anything left behind.
	gQueueA.resize(0);
	gQueueB.resize(0);
	if (gDrawn) {
		for (uint k = 0; k < gPrevDraw.length(); ++k)
			Enqueue(gPrevDraw[k], gPrevDraw[k]);
	}
	gPrevDraw.resize(0);

	// Join each front cell to its TWO nearest front neighbours. Linking every
	// pair within range drew a mesh of four-plus lines per cell; two gives a
	// contour.
	const float span = float(AiTerrainWidth()) / float(SEAM_N) * 1.6f;
	for (uint k = 0; k < gPerim.length(); ++k) {
		if (gEdge[k] != FRONT)
			continue;   // the back is a danger zone, but it is not the front
		int drawn = 0;
		for (uint m = 0; (m < gPerim.length()) && (drawn < 2); ++m) {
			if ((m == k) || (gEdge[m] != FRONT))
				continue;
			if (gPerim[k].distance2D(gPerim[m]) > span)
				continue;
			Enqueue(gPerim[k], gPerim[m]);
			++drawn;
		}
		gPrevDraw.insertLast(gPerim[k]);
	}
	gDrawn = true;

	// Chokepoints must be REDRAWN, not drawn once. BAR ships the "Auto mapmark
	// eraser" widget (luaui/Widgets/map_auto_mapmark_eraser.lua) with
	// eraseTime = 60, which deletes every mark 60 seconds after it appears. A
	// draw-once layer therefore vanishes a minute in. That same widget is why
	// marks cannot accumulate, so the erase bookkeeping here is belt and braces.
	for (uint k = 0; k < gIdx.length(); ++k) {
		AIFloat3 e1, e2;
		if (ai.GetChokePointEnds(gIdx[k], e1, e2))
			Enqueue(e1, e2);
	}
}

}  // namespace Front
