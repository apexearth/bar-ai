namespace Front {

// Which map corridors are ours, which are the enemy's, and which are the seam
// between them.
//
// The topology is BWEM's, computed by the engine every game (see CHANGES.md --
// it was unreachable until the GetChokePoint* bindings). Classification lives
// here rather than in C++ so the thresholds can be retuned without a rebuild.

// A gap narrower than this is an artefact between interior areas, not something
// an army could hold; wider than this is open ground no line would cover.
const float MIN_WIDTH = 80.f;
const float MAX_WIDTH = 2000.f;

// Ownership is read from ally and enemy influence SEPARATELY, not from their
// difference. Measured on Comet Catcher: a corridor beside our base reads net
// 77, one nobody has been near reads exactly 0. Classifying on the difference
// made both of those "balanced", so empty no-man's-land was indistinguishable
// from a genuine seam -- and empty ground is where most of the map sits.
// A seam requires BOTH sides actually present.
//
// "Present" is RELATIVE, not a fixed number. Influence runs to ~290 where a
// team is massed, and a flat threshold of 1.0 called any faint bleed presence --
// which labelled ground OURS that we were nowhere near, because with no enemy
// seen the ally > foe * DOMINANCE test passes on almost nothing. So the bar for
// each side is a fraction of that side's OWN strongest reading this scan, with
// an absolute floor for the opening minutes when everything is small.
// The floor must stay tiny. The two fields are NOT on the same scale: ally
// influence counts everything we own and peaks around 520, while enemy
// influence counts only KNOWN enemy units and peaks under 33 in the same scan.
// A floor of 5 erased the enemy field completely -- every AI read cFoe=0 for a
// whole game -- which made the front vanish rather than move. The per-side
// fraction is what does the work; the floor only guards the opening seconds.
const float PRESENCE_FLOOR = 1.0f;
const float PRESENCE_FRAC = 0.15f;
const float DOMINANCE = 2.0f;   // one side this many times the other owns it
// A seam cell within this of a chokepoint counts as being IN that corridor.
const float CHOKE_NEAR = 600.f;

// Chokepoints do not move, so the geometry is gathered once. Ownership does
// move, so it is re-read on a timer.
const int RECLASSIFY = 10 * SECOND;

enum Owner { EMPTY = 0, OURS = 1, CONTESTED = 2, THEIRS = 3 };

array<int> gIdx;        // indices into the engine's chokepoint list
array<int> gOwner;      // parallel to gIdx
int gNextClassify = 0;
bool gGathered = false;

void Gather()
{
	if (gGathered)
		return;
	gGathered = true;
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

int Classify(const AIFloat3& in pos)
{
	const float ally = ai.GetAllyInflAt(pos);
	const float foe = ai.GetEnemyInflAt(pos);
	if ((ally < gPresAlly) && (foe < gPresFoe))
		return EMPTY;
	if (ally > foe * DOMINANCE)
		return OURS;
	if (foe > ally * DOMINANCE)
		return THEIRS;
	return CONTESTED;
}

void Update()
{
	Gather();
	if (ai.frame < gNextClassify)
		return;
	gNextClassify = ai.frame + RECLASSIFY;

	ScanSeam();   // sets the presence bars that Classify reads
	for (uint k = 0; k < gIdx.length(); ++k)
		gOwner[k] = Classify(ai.GetChokePointPos(gIdx[k]));
	AiLog("apex: frontline ours=" + CountOf(OURS)
			+ " contested=" + CountOf(CONTESTED)
			+ " theirs=" + CountOf(THEIRS)
			+ " empty=" + CountOf(EMPTY)
			+ " seam=" + SeamSize() + " cAlly=" + gDbgAlly + " cFoe=" + gDbgFoe
			+ " bar=" + int(gPresAlly) + "/" + int(gPresFoe)
			+ " box=" + SeamBox());

	Draw();
}

// The front line, read off the influence field.
//
// Measured before this existed: terrain chokepoints are NOT where the fighting
// is. On Jade 8v8 at 10 min, 63 usable chokepoints classified as 23 ours / 40
// empty / 0 contested / 0 theirs -- while a 40x40 sweep of the same map at the
// same moment found 277 cells with enemy presence and 155 with BOTH sides
// present. The contest is real and none of it lands on a chokepoint, because
// BWEM chokepoints on these maps are base entrances and interior pockets and
// the fighting happens in open ground.
//
// So the seam is sampled directly: grid cells where both sides are present.
// Chokepoints stay useful as a filter -- a seam cell that also sits in a
// corridor is worth far more per tower than one in the open -- but they cannot
// define the line by themselves.
// Each AI keeps its OWN influence map, built from what that AI personally knows.
// Measured on Jade 8v8: forward teams read 72-82 enemy cells and a 55-64 cell
// seam, while rear teams read cFoe=0 and no seam at all, in the same game at the
// same moment. So a rear player computing this alone concludes there is no front
// line. Whatever consumes the seam has to share it across the team rather than
// trust the local read -- see Factory's PublishTeamValue/ReadTeamValue.
const int SEAM_N = 40;          // grid resolution per axis
array<AIFloat3> gSeam;
array<bool> gHot;   // parallel to gSeam: this perimeter cell faces known enemy
int gDbgAlly = 0;
int gDbgFoe = 0;
float gPresAlly = PRESENCE_FLOOR;
float gPresFoe = PRESENCE_FLOOR;

AIFloat3 GridPos(int i, int j)
{
	AIFloat3 p;
	p.x = float(AiTerrainWidth()) * (float(i) + .5f) / float(SEAM_N);
	p.z = float(AiTerrainHeight()) * (float(j) + .5f) / float(SEAM_N);
	return p;
}

void ScanSeam()
{
	gSeam.resize(0);
	gHot.resize(0);
	gDbgAlly = 0; gDbgFoe = 0;

	// Pass one: how strong does each side get anywhere? The bars follow from it.
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
	gPresAlly = maxAlly * PRESENCE_FRAC;
	if (gPresAlly < PRESENCE_FLOOR) gPresAlly = PRESENCE_FLOOR;
	gPresFoe = maxFoe * PRESENCE_FRAC;
	if (gPresFoe < PRESENCE_FLOOR) gPresFoe = PRESENCE_FLOOR;

	// Pass two: mark presence per cell.
	array<bool> ally(SEAM_N * SEAM_N);
	array<bool> foe(SEAM_N * SEAM_N);
	for (int i = 0; i < SEAM_N; ++i) {
		for (int j = 0; j < SEAM_N; ++j) {
			const AIFloat3 p = GridPos(i, j);
			const bool a = (ai.GetAllyInflAt(p) >= gPresAlly);
			const bool f = (ai.GetEnemyInflAt(p) >= gPresFoe);
			ally[i * SEAM_N + j] = a;
			foe[i * SEAM_N + j] = f;
			if (a) ++gDbgAlly;
			if (f) ++gDbgFoe;
		}
	}

	// The front is the OUTER EDGE OF OUR OWN TERRITORY, and the enemy field only
	// colours it in.
	//
	// Two earlier definitions failed against measurement. "Cells where both sides
	// are present" found nothing: 339 ally cells and 56 enemy cells in one scan
	// with ZERO holding both, because where one side is strong the other reads
	// ~0. "Cells on the boundary between the two fields" found 2-3 cells, because
	// enemy influence counts only KNOWN enemy units and is far too sparse to
	// draw a line with.
	//
	// Our own perimeter needs no vision to compute, exists from minute one, and
	// is what a player actually means by their front: the edge of what we hold.
	// A perimeter cell facing known enemy influence is HOT -- that is where the
	// fighting is -- and the rest is the quiet flank that still has to be held.
	for (int i = 0; i < SEAM_N; ++i) {
		for (int j = 0; j < SEAM_N; ++j) {
			const int me = i * SEAM_N + j;
			if (!ally[me])
				continue;
			bool edge = false;
			bool hot = false;
			for (int di = -1; di <= 1; ++di) {
				for (int dj = -1; dj <= 1; ++dj) {
					if ((di == 0) && (dj == 0))
						continue;
					const int ni = i + di;
					const int nj = j + dj;
					if ((ni < 0) || (nj < 0) || (ni >= SEAM_N) || (nj >= SEAM_N))
						continue;   // the map edge is not a front
					const int nb = ni * SEAM_N + nj;
					if (!ally[nb])
						edge = true;
					if (foe[nb])
						hot = true;
				}
			}
			if (!edge)
				continue;
			gSeam.insertLast(GridPos(i, j));
			gHot.insertLast(hot);
		}
	}
}

// Nearest point on the front to `from`, if there is a front at all.
bool SeamNear(const AIFloat3& in from, AIFloat3& out spot)
{
	float best = -1.f;
	for (uint k = 0; k < gSeam.length(); ++k) {
		const float d = gSeam[k].distance2D(from);
		if ((best < 0.f) || (d < best)) {
			best = d;
			spot = gSeam[k];
		}
	}
	return best >= 0.f;
}

// A seam cell that also sits in a corridor: the best metal-per-tower on the map.
// Returns false when the front is in open ground, which is the common case.
bool SeamChoke(const AIFloat3& in from, AIFloat3& out spot)
{
	float best = -1.f;
	for (uint k = 0; k < gSeam.length(); ++k) {
		for (uint c = 0; c < gIdx.length(); ++c) {
			const AIFloat3 cp = ai.GetChokePointPos(gIdx[c]);
			if (cp.distance2D(gSeam[k]) > CHOKE_NEAR)
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

uint SeamSize() { return gSeam.length(); }

// Bounding box of the seam this AI computed, to tell a bottom-biased READ from
// a drawing layer that is dropping the top of the map.
string SeamBox()
{
	if (gSeam.length() == 0)
		return "none";
	float x0 = gSeam[0].x, x1 = gSeam[0].x, z0 = gSeam[0].z, z1 = gSeam[0].z;
	for (uint k = 1; k < gSeam.length(); ++k) {
		if (gSeam[k].x < x0) x0 = gSeam[k].x;
		if (gSeam[k].x > x1) x1 = gSeam[k].x;
		if (gSeam[k].z < z0) z0 = gSeam[k].z;
		if (gSeam[k].z > z1) z1 = gSeam[k].z;
	}
	return "x" + int(x0) + "-" + int(x1) + ",z" + int(z0) + "-" + int(z1);
}

// Positions of every seam corridor, nearest first from `from`. This is the list
// the defence and army work in the next steps consume.
uint Contested(const AIFloat3& in from, array<AIFloat3>& names)
{
	names.resize(0);
	array<float> dist;
	for (uint k = 0; k < gIdx.length(); ++k) {
		if (gOwner[k] != CONTESTED)
			continue;
		const AIFloat3 p = ai.GetChokePointPos(gIdx[k]);
		const float d = p.distance2D(from);
		uint at = 0;
		while ((at < dist.length()) && (dist[at] < d))
			++at;
		dist.insertAt(at, d);
		names.insertAt(at, p);
	}
	return names.length();
}

// Count by owner, for logging and for gates that only care how much seam exists.
uint CountOf(int owner)
{
	uint n = 0;
	for (uint k = 0; k < gOwner.length(); ++k) {
		if (gOwner[k] == owner)
			++n;
	}
	return n;
}

// ---------------------------------------------------------------------------
// Debug overlay. These are ORDINARY MAP MARKERS -- allies and spectators see
// them. Leave DRAW off for anything but a watched game.
const bool DRAW = true;
int gDrawnAt = -1;

void Draw()
{
	if (!DRAW)
		return;

	// Every AI draws its OWN seam, so what you see is the union of what the team
	// knows. Measured: in one Jade 8v8, 248 of 400 samples read cFoe=0 -- rear
	// players see no enemy at all -- so drawing from a single team showed one
	// player's slice of the front and left the rest of the map blank.
	for (uint k = 0; k < gSeam.length(); ++k) {
		if (gDrawnAt >= 0)
			ai.DrawErase(gSeam[k]);
		ai.DrawPoint(gSeam[k], gHot[k] ? "FRONT-HOT" : "front");
	}
	gDrawnAt = ai.frame;

	// The chokepoint layer is identical for every AI, so only one draws it.
	if (ai.teamId != Factory::ElectorTeamId())
		return;

	for (uint k = 0; k < gIdx.length(); ++k) {
		const int i = gIdx[k];
		const AIFloat3 c = ai.GetChokePointPos(i);
		if (gDrawnAt >= 0)
			ai.DrawErase(c);

		string tag;
		if (gOwner[k] == OURS)			tag = "OURS";
		else if (gOwner[k] == THEIRS)	tag = "THEIRS";
		else if (gOwner[k] == CONTESTED)	tag = "CONTESTED";
		else							tag = "empty";

		ai.DrawPoint(c, tag + " w" + int(ai.GetChokePointWidth(i)));

		AIFloat3 e1, e2;
		if (ai.GetChokePointEnds(i, e1, e2))
			ai.DrawLine(e1, e2);   // the gap an army or a wall would span
	}
}

}  // namespace Front
