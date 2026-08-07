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
const int RECLASSIFY = 10 * SECOND;
const int SEAM_N = 40;

enum Owner { EMPTY = 0, OURS = 1, CONTESTED = 2, THEIRS = 3 };
enum Edge { NONE = 0, FRONT = 1, BACK = 2 };

array<int> gIdx;
array<int> gOwner;
int gNextClassify = 0;
bool gGathered = false;

array<AIFloat3> gPerim;    // the whole ring around our territory
array<int> gEdge;          // parallel to gPerim: FRONT, BACK or NONE
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

void Scan()
{
	gPerim.resize(0);
	gEdge.resize(0);
	gDbgAlly = 0;
	gDbgFoe = 0;

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
			const bool a = (ai.GetAllyInflAt(p) >= gPresAlly);
			ours[me] = a;
			if (a) {
				++gDbgAlly;
				ox += p.x; oz += p.z; ow += 1.f;
			}
			// Enemy sightings are REMEMBERED, not sampled. A raid that passes
			// through is gone from the influence map seconds later, but the fact
			// that their territory lies that way does not stop being true.
			if (ai.GetEnemyInflAt(p) >= gPresFoe) {
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
	gFoeKnown = (fw > 0.f);
	if (gFoeKnown) {
		gFoeMid.x = fx / fw;
		gFoeMid.z = fz / fw;
	}

	const float dirx = gFoeMid.x - gOurMid.x;
	const float dirz = gFoeMid.z - gOurMid.z;
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
			if (!gFoeKnown) {
				gEdge.insertLast(NONE);
			} else {
				const float facing = (p.x - gOurMid.x) * dirx + (p.z - gOurMid.z) * dirz;
				gEdge.insertLast((facing > 0.f) ? FRONT : BACK);
			}
		}
	}
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
	if (ai.frame < gNextClassify)
		return;
	gNextClassify = ai.frame + RECLASSIFY;

	Scan();
	for (uint k = 0; k < gIdx.length(); ++k)
		gOwner[k] = Classify(ai.GetChokePointPos(gIdx[k]));

	AiLog("apex: frontline perim=" + gPerim.length()
			+ " front=" + CountEdge(FRONT) + " back=" + CountEdge(BACK)
			+ " foeKnown=" + (gFoeKnown ? 1 : 0)
			+ " cAlly=" + gDbgAlly + " cFoe=" + gDbgFoe
			+ " bar=" + int(gPresAlly) + "/" + int(gPresFoe));

	Draw();
}

// Nearest point on the front to `from`. False while the front is still unknown,
// which is the honest answer for the opening of a game.
bool FrontNear(const AIFloat3& in from, AIFloat3& out spot)
{
	float best = -1.f;
	for (uint k = 0; k < gPerim.length(); ++k) {
		if (gEdge[k] != FRONT)
			continue;
		const float d = gPerim[k].distance2D(from);
		if ((best < 0.f) || (d < best)) {
			best = d;
			spot = gPerim[k];
		}
	}
	return best >= 0.f;
}

// A front cell that also sits in a corridor: the best metal-per-tower there is.
bool FrontChoke(const AIFloat3& in from, AIFloat3& out spot)
{
	float best = -1.f;
	for (uint k = 0; k < gPerim.length(); ++k) {
		if (gEdge[k] != FRONT)
			continue;
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

uint FrontSize() { return CountEdge(FRONT); }
bool IsFrontKnown() { return gFoeKnown; }

// ---------------------------------------------------------------------------
// Debug overlay. Map LINES, not points. A point is a PING -- it fires an alert
// and a minimap flash -- which at this density is unreadable. Lines just draw.
// Allies and spectators see these. Off for anything but a watched game.
const bool DRAW = true;

void Draw()
{
	if (!DRAW)
		return;

	if (gDrawn) {
		for (uint k = 0; k < gPrevDraw.length(); ++k)
			ai.DrawErase(gPrevDraw[k]);
	}
	gPrevDraw.resize(0);

	// Join each front cell to its ring neighbours so it renders as a contour
	// rather than a cloud. 1.6 cells catches the 8 neighbours and nothing more.
	const float span = float(AiTerrainWidth()) / float(SEAM_N) * 1.6f;
	for (uint k = 0; k < gPerim.length(); ++k) {
		if (gEdge[k] == BACK)
			continue;   // the back is a danger zone, but it is not the front
		for (uint m = k + 1; m < gPerim.length(); ++m) {
			if (gEdge[m] == BACK)
				continue;
			if (gPerim[k].distance2D(gPerim[m]) > span)
				continue;
			ai.DrawLine(gPerim[k], gPerim[m]);
		}
		gPrevDraw.insertLast(gPerim[k]);
	}
	gDrawn = true;

	// The chokepoint layer is identical for every AI, so only one draws it.
	if (ai.teamId != Factory::ElectorTeamId())
		return;
	for (uint k = 0; k < gIdx.length(); ++k) {
		AIFloat3 e1, e2;
		if (ai.GetChokePointEnds(gIdx[k], e1, e2))
			ai.DrawLine(e1, e2);
	}
}

}  // namespace Front
