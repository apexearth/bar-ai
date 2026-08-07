namespace Front {

// Which map corridors are ours, which are the enemy's, and which are the seam
// between them.
//
// The topology is BWEM's, computed by the engine every game (see CHANGES.md --
// it was unreachable until the GetChokePoint* bindings). Classification lives
// here rather than in C++ so the thresholds can be retuned without a rebuild.

// A gap narrower than this is an artefact between interior areas, not something
// an army could hold; wider than this is open ground no line would cover.
const float MIN_WIDTH = 200.f;
const float MAX_WIDTH = 2000.f;

// Ownership is read from ally and enemy influence SEPARATELY, not from their
// difference. Measured on Comet Catcher: a corridor beside our base reads net
// 77, one nobody has been near reads exactly 0. Classifying on the difference
// made both of those "balanced", so empty no-man's-land was indistinguishable
// from a genuine seam -- and empty ground is where most of the map sits.
// A seam requires BOTH sides actually present.
const float PRESENCE = 1.0f;    // below this, nobody is meaningfully there
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
	if ((ally < PRESENCE) && (foe < PRESENCE))
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

	for (uint k = 0; k < gIdx.length(); ++k)
		gOwner[k] = Classify(ai.GetChokePointPos(gIdx[k]));
	AiLog("apex: frontline ours=" + CountOf(OURS)
			+ " contested=" + CountOf(CONTESTED)
			+ " theirs=" + CountOf(THEIRS)
			+ " empty=" + CountOf(EMPTY)
			+ " seam=" + SeamSize() + " cAlly=" + gDbgAlly + " cFoe=" + gDbgFoe);

	ScanSeam();
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
int gDbgAlly = 0;
int gDbgFoe = 0;

void ScanSeam()
{
	gSeam.resize(0);
	gDbgAlly = 0; gDbgFoe = 0;
	const float w = AiTerrainWidth();
	const float h = AiTerrainHeight();
	for (int i = 0; i < SEAM_N; ++i) {
		for (int j = 0; j < SEAM_N; ++j) {
			AIFloat3 p;
			p.x = w * (float(i) + .5f) / float(SEAM_N);
			p.z = h * (float(j) + .5f) / float(SEAM_N);
			const float a = ai.GetAllyInflAt(p);
			const float f = ai.GetEnemyInflAt(p);
			if (a >= PRESENCE) ++gDbgAlly;
			if (f >= PRESENCE) ++gDbgFoe;
			if ((a < PRESENCE) || (f < PRESENCE))
				continue;
			gSeam.insertLast(p);
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
	if (!DRAW || (ai.teamId != Factory::ElectorTeamId()))
		return;   // one team draws, or every AI stacks markers on the same spot

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
	for (uint k = 0; k < gSeam.length(); ++k) {
		if (gDrawnAt >= 0)
			ai.DrawErase(gSeam[k]);
		ai.DrawPoint(gSeam[k], "FRONT");
	}
	gDrawnAt = ai.frame;
}

}  // namespace Front
